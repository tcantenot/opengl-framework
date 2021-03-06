#line 1
////////////////////////////////////////////////////////////////////////////////
// Implicit Subdivition Sahder for Terrain Rendering (using a geometry shader)
//

layout (std430, binding = BUFFER_BINDING_SUBD1)
readonly buffer SubdBufferIn {
	uvec2 u_SubdBufferIn[];
};

layout (std430, binding = BUFFER_BINDING_SUBD2)
buffer SubdBufferOut {
	uvec2 u_SubdBufferOut[];
};

layout (std430, binding = BUFFER_BINDING_GEOMETRY_VERTICES)
readonly buffer VertexBuffer {
	vec4 u_VertexBuffer[];
};

layout (std430, binding = BUFFER_BINDING_GEOMETRY_INDEXES)
readonly buffer IndexBuffer {
	uint u_IndexBuffer[];
};

layout (binding = BUFFER_BINDING_SUBD_COUNTER)
uniform atomic_uint u_SubdBufferCounter;

struct Transform {
	mat4 modelView;
	mat4 projection;
	mat4 modelViewProjection;
	mat4 viewInv;
};

layout(std140, row_major, binding = BUFFER_BINDING_TRANSFORMS)
uniform Transforms {
	Transform u_Transform;
};

uniform sampler2D u_DmapSampler;
uniform float u_DmapFactor;
uniform float u_LodFactor;

// displacement map
float dmap(vec2 pos)
{
#if 0
    return cos(20.0 * pos.x) * cos(20.0 * pos.y) / 2.0 * u_DmapFactor;
#else
    return (texture(u_DmapSampler, pos * 0.5 + 0.5).x) * u_DmapFactor;
#endif
}

float distanceToLod(float z, float lodFactor)
{
    // Note that we multiply the result by two because the triangle's
    // edge lengths decreases by half every two subdivision steps.
    return -2.0 * log2(clamp(z * lodFactor, 0.0f, 1.0f));
}


// -----------------------------------------------------------------------------
/**
 * Vertex Shader
 *
 * The vertex shader is empty
 */
#ifdef VERTEX_SHADER
void main(void)
{ }
#endif

// -----------------------------------------------------------------------------
/**
 * Geometry Shader
 *
 * This geometry shader is responsible for updating the
 * subdivision buffer and sending visible geometry to the rasterizer.
 */
#ifdef GEOMETRY_SHADER
layout(points) in;
layout(triangle_strip, max_vertices = VERTICES_OUT) out;
layout(location = 0) out vec2 o_TexCoord;

float computeLod(vec3 c)
{
#if FLAG_DISPLACE
    c.z+= dmap(u_Transform.viewInv[3].xy);
#endif

    vec3 cxf = (u_Transform.modelView * vec4(c, 1)).xyz;
    float z = length(cxf);

    return distanceToLod(z, u_LodFactor);
}

float computeLod(in vec3 v[3])
{
    vec3 c = (v[1] + v[2]) / 2.0;
    return computeLod(c);
}

void writeKey(uint primID, uint key)
{
    uint idx = atomicCounterIncrement(u_SubdBufferCounter);

    u_SubdBufferOut[idx] = uvec2(primID, key);
}

void updateSubdBuffer(uint primID, uint key, int targetLod, int parentLod)
{
    // extract subdivision level associated to the key
    int keyLod = findMSB(key);

    // update the key accordingly
    if (/* subdivide ? */ keyLod < targetLod && !isLeafKey(key)) {
        uint children[2]; childrenKeys(key, children);

        writeKey(primID, children[0]);
        writeKey(primID, children[1]);
    } else if (/* keep ? */ keyLod < (parentLod + 1)) {
        writeKey(primID, key);
    } else /* merge ? */ {
        if (/* is root ? */isRootKey(key)) {
            writeKey(primID, key);
        } else if (/* is zero child ? */isChildZeroKey(key)) {
            writeKey(primID, parentKey(key));
        }
    }
}

void main()
{
    // get threadID (each key is associated to a thread)
    int threadID = gl_PrimitiveIDIn;

    // get coarse triangle associated to the key
    uint primID = u_SubdBufferIn[threadID].x;
    vec3 v_in[3] = vec3[3](
        vec3(u_VertexBuffer[u_IndexBuffer[primID * 3    ]].xyz),
        vec3(u_VertexBuffer[u_IndexBuffer[primID * 3 + 1]].xyz),
        vec3(u_VertexBuffer[u_IndexBuffer[primID * 3 + 2]].xyz)
    );

    // compute distance-based LOD
    uint key = u_SubdBufferIn[threadID].y;
    vec3 v[3], vp[3]; subd(key, v_in, v, vp);
    int targetLod = int(computeLod(v));
    int parentLod = int(computeLod(vp));
#if FLAG_FREEZE
    targetLod = parentLod = findMSB(key);
#endif
    updateSubdBuffer(primID, key, targetLod, parentLod);

#if FLAG_CULL
    // Cull invisible nodes
    mat4 mvp = u_Transform.modelViewProjection;
    vec3 bmin = min(min(v[0], v[1]), v[2]);
    vec3 bmax = max(max(v[0], v[1]), v[2]);

    // account for displacement in bound computations
#   if FLAG_DISPLACE
    bmin.z = 0;
    bmax.z = u_DmapFactor;
#   endif

    if (/* is visible ? */frustumCullingTest(mvp, bmin, bmax)) {
#else
    if (true) {
#endif // FLAG_CULL
        // set tess levels
        int edgeCnt = PATCH_TESS_LEVEL;
        float edgeLength = 1.0 / float(edgeCnt);

        for (int i = 0; i < edgeCnt; ++i) {
            int vertexCnt = 2 * i + 3;

            // start a strip
            for (int j = 0; j < vertexCnt; ++j) {
                int ui = j >> 1;
                int vi = (edgeCnt - 1) - (i - (j & 1));
                vec2 tessCoord = vec2(ui, vi) * edgeLength;
                vec3 finalVertex = berp(v, tessCoord);

#if FLAG_DISPLACE
                finalVertex.z+= dmap(finalVertex.xy);
#endif

                o_TexCoord = tessCoord;
                gl_Position = u_Transform.modelViewProjection * vec4(finalVertex, 1);
                EmitVertex();
            }
            EndPrimitive();
        }
    }

}
#endif

// -----------------------------------------------------------------------------
/**
 * Fragment Shader
 *
 * This fragment shader is responsible for shading the final geometry.
 */
#ifdef FRAGMENT_SHADER
layout(location = 0) in vec2 i_TexCoord;
layout(location = 0) out vec4 o_FragColor;

void main()
{
    vec3 c[3] = vec3[3](vec3(0.0,1.0,1.0)/4.0,
                        vec3(0.86,0.00,0.00),
                        vec3(1.0,0.50,0.00)/1.0);
    vec3 color = berp(c, i_TexCoord);

    o_FragColor = vec4(color, 1);
}

#endif
