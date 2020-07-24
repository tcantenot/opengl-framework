/* terrain_common.glsl - public domain
    (created by Jonathan Dupuy and Cyril Crassin)
*/

//The rest of the code is inside those headers which are included by the C-code:
//Include isubd.glsl

layout(std430, binding = BUFFER_BINDING_GEOMETRY_VERTICES)
readonly buffer VertexBuffer {
    vec4 u_VertexBuffer[];
};

layout(std430, binding = BUFFER_BINDING_GEOMETRY_INDEXES)
readonly buffer IndexBuffer {
    uint u_IndexBuffer[];
};

layout(binding = BUFFER_BINDING_SUBD_COUNTER)
uniform atomic_uint u_SubdBufferCounter;

layout(std430, binding = BUFFER_BINDING_SUBD2)
buffer SubdBufferOut {
    uvec2 u_SubdBufferOut[];
};

struct Transform {
    mat4 localToWorld;
    mat4 worldToView;
    mat4 viewToLocal;
    mat4 modelView;
    mat4 projection;
    mat4 modelViewProjection;
	mat4 _pad0;
	mat4 _pad1;
};

layout(std140, column_major, binding = BUFFER_BINDING_TRANSFORMS)
uniform Transforms {
    Transform u_Transform;
};

uniform sampler2D u_DmapSampler; // displacement map
uniform sampler2D u_SmapSampler; // slope map
uniform float u_DmapFactor;
uniform float u_LodFactor;


vec2 intValToColor2(int keyLod)
{
    keyLod = keyLod % 64;

    int bx = (keyLod & 0x1) | ((keyLod >> 1) & 0x2) | ((keyLod >> 2) & 0x4);
    int by = ((keyLod >> 1) & 0x1) | ((keyLod >> 2) & 0x2) | ((keyLod >> 3) & 0x4);

    return vec2(float(bx) / 7.0f, float(by) / 7.0f);
}

// displacement map
float dmap(vec2 pos)
{
    return (texture(u_DmapSampler, pos * 0.5 + 0.5).x) * u_DmapFactor;
}

float distanceToLod(float z, float lodFactor)
{
    // Note that we multiply the result by two because the triangle's
    // edge lengths decreases by half every two subdivision steps.
    return -2.0 * log2(clamp(z * lodFactor, 0.0f, 1.0f));
}


float computeLod(vec3 localPos)
{
	// Need to displace vertex to compute distance --> might be costly
	#if 0
		#if FLAG_DISPLACE
		//localPos.z += dmap(u_Transform.viewInv[3].xy);
		localPos.z += dmap(u_Transform.viewToLocal[3].xy);
		#endif
		vec3 cxf = (u_Transform.modelView * vec4(localPos, 1)).xyz;
	#else
		#if FLAG_DISPLACE
		localPos.z += dmap(localPos.xy);
		#endif
		vec3 cxf = (u_Transform.modelView * vec4(localPos, 1)).xyz;
	#endif

    float z = length(cxf); // Radial distance to camera

    return distanceToLod(z, u_LodFactor);
}

float computeLod(in vec4 v[3])
{
    vec3 c = (v[1].xyz + v[2].xyz) / 2.0;
    return computeLod(c);
}
float computeLod(in vec3 v[3])
{
    vec3 c = (v[1].xyz + v[2].xyz) / 2.0;
    return computeLod(c);
}

void writeKey(uint primID, uint key)
{
    uint idx = atomicCounterIncrement(u_SubdBufferCounter);

    u_SubdBufferOut[idx] = uvec2(primID, key);
}

// 1.2.3 Iterative Construction
// The triangles produced by the subdivision are stored as keys inside a buffer that we update iteratively in a ping-pong fashion;
// This double-buffer is referred as the subdivision buffer.
// Because the keys consists of integers, the subdivision buffer is very compact.
// At each iteration, the keys are processed independently in a compute shader, which is set to write in the second buffer.
// There are three possible outcomes for each key:
// it can be subdivided to the next level, downgraded to the previous subdivision level, or conserved as is.

// TODO:
// - optim: it might be possible to avoid useless recomputation of LODs of triangles sufficiently subdivided
//		-> use a bit to signal that the triangle does not need further subdivision?
//		--> does it actually happen often?
void updateSubdBuffer(
    uint primID,
    uint key,
    int targetLod,
    int parentLod,
    bool isVisible
) {
    // Extract subdivision level associated to the key
    int keyLod = findMSB(key);

    // Update the key accordingly

	// Split triangle into two subtriangles
	// --> output the two subtriangles keys for further processing (LOD computation + possible further subdivision)
    if (/* subdivide ? */ keyLod < targetLod && !isLeafKey(key) && isVisible)
	{
        uint children[2]; childrenKeys(key, children);

		// TODO: optimize -> increment atomic counter by 2 at once
        writeKey(primID, children[0]);
        writeKey(primID, children[1]);
    }
	// Keep triangle as it is sufficiently small
    else if (/* keep ? */ keyLod < (parentLod + 1) && isVisible)
	{
        writeKey(primID, key);
    }
	// Triangle is too small, merge it with its sibling
	// --> only child zero output the merge (parent) key
    else /* merge ? */
	{
        if (/* is root ? */isRootKey(key))
        {
            writeKey(primID, key);
        }
#if 1
        else if (/* is zero child ? */isChildZeroKey(key)) {
            writeKey(primID, parentKey(key));
        }
#else
        // Experiments to fix missing triangles when merging
        else {
            int numMergeLevels = keyLod - (parentLod);

            uint mergeMask = (key & ((1 << numMergeLevels) - 1));
            if (mergeMask == 0)
            {
                key = (key >> numMergeLevels);
                writeKey(primID, key);
            }

        }
#endif
    }
}

void updateSubdBuffer(uint primID, uint key, int targetLod, int parentLod)
{
    updateSubdBuffer(primID, key, targetLod, parentLod, true);
}

vec4 shadeFragment(vec2 texCoord)
{
#ifdef FRAGMENT_SHADER0
	vec3 bary = vec3(texCoord.x, texCoord.y, 1.0 - texCoord.x - texCoord.y);
	#if 0
	float minBary = min(min(bary.x, bary.y), bary.z);
	//float delta = abs(dFdx(minBary) + dFdy(minBary));
	//minBary = smoothstep(0, delta, minBary);
	float delta = fwidth(minBary);
	minBary = smoothstep(delta, 2 * delta, minBary);
	#else
	vec3 delta = fwidth(bary);
	bary = smoothstep(delta, 2 * delta, bary);
	float minBary = min(min(bary.x, bary.y), bary.z);
	#endif
	return vec4(minBary);
#endif
    //return vec4(texCoord, 0, 1);
#if SHADING_LOD
    return vec4(texCoord, 0, 1);

#elif SHADING_DIFFUSE
    vec2 s = texture(u_SmapSampler, texCoord).rg * u_DmapFactor;
    vec3 n = normalize(vec3(-s, 1));
    float d = clamp(n.z, 0.0, 1.0);

    return vec4(vec3(d / 3.14159), 1);

#elif SHADING_NORMALS
    vec2 s = texture(u_SmapSampler, texCoord).rg * u_DmapFactor;
    vec3 n = normalize(vec3(-s, 1));

    return vec4(abs(n), 1);

#else
    return vec4(1, 0, 0, 1);
#endif
}

