/* terrain_cs_lod.glsl - public domain
    (created by Jonathan Dupuy and Cyril Crassin)

    This code has dependencies on the following GLSL sources:
    - fcull.glsl
    - isubd.glsl
    - terrain_common.glsl
*/

////////////////////////////////////////////////////////////////////////////////
// Implicit Subdivition Shader for Terrain Rendering
//

layout (std430, binding = BUFFER_BINDING_SUBD1)
readonly buffer SubdBufferIn {
    uvec2 u_SubdBufferIn[];
};


// -----------------------------------------------------------------------------
/**
 * Vertex Shader
 *
 * The vertex shader is empty
 */
#ifdef VERTEX_SHADER
void main()
{ }
#endif

// -----------------------------------------------------------------------------
/**
 * Tessellation Control Shader
 *
 * This tessellaction control shader is responsible for updating the
 * subdivision buffer and sending visible geometry to the rasterizer.
 */
#ifdef TESS_CONTROL_SHADER
layout (vertices = 1) out;
out Patch {
    vec3 vertices[3];
    flat uint key;
} o_Patch[];



void main()
{
    // get threadID (each key is associated to a thread)
    int threadID = gl_PrimitiveID;

    // get coarse triangle associated to the key
    uint primID = u_SubdBufferIn[threadID].x;

	// Note: even if we check the limit of the subdivision buffer, some triangles can be missing
	// if at the beginning of the current iteration we are close to the limit.
	// Indeed the current iteration will potentially produce more triangles and reach the subdivision
	// buffer limit causing previously valid triangles to be thrown out of the buffer.
	// To mitigate the issue, we stop subdivided when we reached some fraction of the max capacity.
	// (it is possible to be prefectly safe if we stop subdividing when we go above 50% occupancy).
	const float kMaxSubdBufferOccupancyBeforeStopping = 0.500001;
	const bool bReachedSubdBufferLimit = false;//(prevIterationsSubdivisions >= (MAX_NUM_SUBDIVISIONS * kMaxSubdBufferOccupancyBeforeStopping));

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

    // compute distance-based LOD
    uint key = u_SubdBufferIn[threadID].y;
    vec3 v[3], vp[3]; subd(key, v_in, v, vp);
    int targetLod = int(computeLod(v));
    int parentLod = int(computeLod(vp));
#if FLAG_FREEZE
    targetLod = parentLod = findMSB(key);
#endif
    updateSubdBuffer(primID, key, targetLod, parentLod, bReachedSubdBufferLimit);

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
        int tessLevel = PATCH_TESS_LEVEL;
        gl_TessLevelInner[0] =
        gl_TessLevelInner[1] =
        gl_TessLevelOuter[0] =
        gl_TessLevelOuter[1] =
        gl_TessLevelOuter[2] = tessLevel;

        // set output data
        o_Patch[gl_InvocationID].vertices = v;
        o_Patch[gl_InvocationID].key = key;
    } else /* is not visible ? */ {
        // cull the geometry
        gl_TessLevelInner[0] =
        gl_TessLevelInner[1] =
        gl_TessLevelOuter[0] =
        gl_TessLevelOuter[1] =
        gl_TessLevelOuter[2] = 0;
    }
}
#endif

// -----------------------------------------------------------------------------
/**
 * Tessellation Evaluation Shader
 *
 * This tessellaction evaluation shader is responsible for placing the
 * geometry properly on the input mesh (here a terrain).
 */
#ifdef TESS_EVALUATION_SHADER
layout (triangles, ccw, equal_spacing) in;
in Patch {
    vec3 vertices[3];
    flat uint key;
} i_Patch[];

layout(location = 0) out vec2 o_TexCoord;

void main()
{
    vec3 v[3] = i_Patch[0].vertices;
    vec4 finalVertex = vec4(berp(v, gl_TessCoord.xy), 1.0);

#if FLAG_DISPLACE
    finalVertex.z+= dmap(finalVertex.xy);
#endif

#if SHADING_LOD
    //o_TexCoord = gl_TessCoord.xy;
    int keyLod = findMSB(i_Patch[0].key);
    vec2 lodColor = intValToColor2(keyLod);
    o_TexCoord = lodColor;
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
