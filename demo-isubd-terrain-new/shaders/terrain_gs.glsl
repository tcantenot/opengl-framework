/* terrain_gs.glsl - public domain
    (created by Jonathan Dupuy and Cyril Crassin)

    This code has dependencies on the following GLSL sources:
    - fcull.glsl
    - isubd.glsl
    - terrain_common.glsl
*/

////////////////////////////////////////////////////////////////////////////////
// Implicit Subdivition Shader for Terrain Rendering (using a geometry shader)
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
layout(triangle_strip, max_vertices = MAX_VERTICES) out;
layout(location = 0) out vec2 o_TexCoord;

void genVertex(in vec3 v[3], vec2 tessCoord, vec2 lodColor)
{
    vec4 finalVertex = vec4(berp(v, tessCoord), 1.0);

#if FLAG_DISPLACE
    finalVertex.z+= dmap(finalVertex.xy);
#endif

#if SHADING_LOD
    o_TexCoord = lodColor;
#else
    o_TexCoord = finalVertex.xy * 0.5 + 0.5;
#endif
    gl_Position = u_Transform.modelViewProjection * finalVertex;
    EmitVertex();
}

void main()
{
    // get threadID (each key is associated to a thread)
    int threadID = gl_PrimitiveIDIn;

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

        int keyLod = findMSB(key);
        vec2 lodColor = intValToColor2(keyLod);

        /*
            The code below generates a tessellated triangle with a single triangle strip.
            The algorithm instances strips of 4 vertices, which produces 2 triangles.
            This is why there is a special case for subd_level == 0, where we expect
            only one triangle.
        */
#if PATCH_SUBD_LEVEL == 0
        genVertex(v, vec2(0, 0), lodColor);
        genVertex(v, vec2(1, 0), lodColor);
        genVertex(v, vec2(0, 1), lodColor);
        EndPrimitive();
#else
        int subdLevel = 2 * PATCH_SUBD_LEVEL - 1;
        int stripCnt = 1 << subdLevel;

        for (int i = 0; i < stripCnt; ++i) {
            uint key = i + stripCnt;
            vec3 vs[3];  subd(key, v, vs);

            genVertex(vs, vec2(0.0f, 1.0f), lodColor);
            genVertex(vs, vec2(0.0f, 0.0f), lodColor);
            genVertex(vs, vec2(0.5f, 0.5f), lodColor);
            genVertex(vs, vec2(1.0f, 0.0f), lodColor);
        }
        EndPrimitive();
#endif
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
    o_FragColor = shadeFragment(i_TexCoord);
}

#endif
