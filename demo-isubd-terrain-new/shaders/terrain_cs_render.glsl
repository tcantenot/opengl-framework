/* terrain_cs_render.glsl - public domain
    (created by Jonathan Dupuy and Cyril Crassin)

    This code has dependencies on the following GLSL sources:
    - isubd.glsl
    - terrain_common.glsl
*/

////////////////////////////////////////////////////////////////////////////////
// Implicit Subdivition Shader for Terrain Rendering
//

layout (std430, binding = BUFFER_BINDING_CULLED_SUBD)
buffer CulledSubdBuffer {
    uvec2 u_CulledSubdBuffer[];
};


// -----------------------------------------------------------------------------
/**
 * Compute LoD Shader
 *
 * This compute shader is responsible for updating the subdivision
 * buffer and visible buffer that will be sent to the rasterizer.
 *
 * 1.2.4 Conversion to Explicit Geometry
 *   We instantiate a triangle for each subdivision key located in our subdivision buffer.
 */
#ifdef VERTEX_SHADER
layout(location = 0) in vec2 i_TessCoord;
layout(location = 0) out vec2 o_TexCoord;

void main()
{
    // get threadID (each key is associated to a thread)
    int threadID = gl_InstanceID;

    // get coarse triangle associated to the key
    uint primID = u_CulledSubdBuffer[threadID].x;
	
	#if 0
    vec3 v_in[3] = vec3[3](
        u_VertexBuffer[u_IndexBuffer[primID * 3    ]].xyz,
        u_VertexBuffer[u_IndexBuffer[primID * 3 + 1]].xyz,
        u_VertexBuffer[u_IndexBuffer[primID * 3 + 2]].xyz
    );
	#else
	// Terrain-specific optimization: the base primitive for the terrain is a quad with 2 triangles so primID is in { 0, 1 }
	// --> reconstruct the triangle vertices from the primID { 0, 1 } w/o fetching from the index and vertex buffer
	vec3 v_in[3] = vec3[3](
		primID > 0 ? vec3(+1.0f, +1.0f, 0.0f) : vec3(-1.0f, -1.0f, 0.0f),
		primID > 0 ? vec3(-1.0f, +1.0f, 0.0f) : vec3(+1.0f, -1.0f, 0.0f),
		primID > 0 ? vec3(+1.0f, -1.0f, 0.0f) : vec3(-1.0f, +1.0f, 0.0f)
	);
	#endif

    // compute sub-triangle associated to the key
    uint key = u_CulledSubdBuffer[threadID].y;
    vec3 v[3]; subd(key, v_in, v);

    // compute vertex location
    vec4 finalVertex = vec4(berp(v, i_TessCoord), 1);
#if FLAG_DISPLACE
    finalVertex.z+= dmap(finalVertex.xy);
#endif

#if SHADING_LOD
    //o_TexCoord = i_TessCoord.xy;
    int keyLod = findMSB(key);
    o_TexCoord = intValToColor2(keyLod);
#else
    o_TexCoord = finalVertex.xy * 0.5 + 0.5;
#endif

    gl_Position = u_Transform.modelViewProjection * finalVertex;
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
    o_FragColor = shadeFragment(i_TexCoord);
}
#endif

