/* terrain_cs_lod.glsl - public domain
    (created by Jonathan Dupuy and Cyril Crassin)

    This code has dependencies on the following GLSL sources:
    - fcull.glsl
    - isubd.glsl
    - terrain_common.glsl
*/

////////////////////////////////////////////////////////////////////////////////
// Implicit Subdivision Shader for Terrain Rendering
//

layout (std430, binding = BUFFER_BINDING_SUBD1)
readonly buffer SubdBufferIn {
    uvec2 u_SubdBufferIn[];
};

layout (std430, binding = BUFFER_BINDING_VISIBLE_SUBD)
buffer CulledSubdBuffer {
    uvec2 u_CulledSubdBuffer[];
};

layout(std430, binding = BUFFER_BINDING_INDIRECT_COMMAND)
buffer IndirectCommandBuffer {
	uint u_IndirectCommand[8];
};

//layout (binding = BUFFER_BINDING_SUBD_COUNTER, offset = 4)
layout(binding = BUFFER_BINDING_VISIBLE_SUBD_COUNTER)
uniform atomic_uint u_CulledSubdBufferCounter;



// -----------------------------------------------------------------------------
/**
 * Compute LoD Shader
 *
 * This compute shader is responsible for updating the subdivision
 * buffer and visible buffer that will be sent to the rasterizer.
 */
#ifdef COMPUTE_SHADER
layout (local_size_x = COMPUTE_THREAD_COUNT,
        local_size_y = 1,
        local_size_z = 1) in;

// TODO:
// - send size of subdivision buffer to avoid overflow
//  -> is it possible to detect overflow CPU-side?
void main()
{
    // get threadID (each key is associated to a thread)
    uint threadID = gl_GlobalInvocationID.x;

    // early abort if the threadID exceeds the size of the subdivision buffer
    //if (threadID >= atomicCounter(u_PreviousSubdBufferCounter))

	uint prevIterationsSubdivisions = u_IndirectCommand[7];
	if (threadID >= prevIterationsSubdivisions || threadID >= MAX_NUM_SUBDIVISIONS)
        return;

	// Note: even if we check the limit of the subdivision buffer, some triangles can be missing
	// if at the beginning of the current iteration we are close to the limit.
	// Indeed the current iteration will potentially produce more triangles and reach the subdivision
	// buffer limit causing previously valid triangles to be thrown out of the buffer.
	// To mitigate the issue, we stop subdivided when we reached some fraction of the max capacity.
	// (it is possible to be prefectly safe if we stop subdividing when we go above 50% occupancy).
	const float kMaxSubdBufferOccupancyBeforeStopping = 0.500001;
	const bool bReachedSubdBufferLimit = (prevIterationsSubdivisions >= (MAX_NUM_SUBDIVISIONS * kMaxSubdBufferOccupancyBeforeStopping));

    // get coarse triangle associated to the key
    uint primID = u_SubdBufferIn[threadID].x;

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
	#if FLAG_DISPLACE
    bmin.z = 0;
    bmax.z = u_DmapFactor;
	#endif

    // update CulledSubdBuffer
    if (/* is visible ? */frustumCullingTest(mvp, bmin, bmax)) {
#else
    if (true) {
#endif // FLAG_CULL
        // write key
        //uint idx = atomicCounterIncrement(u_CulledSubdBufferCounter[1]);
		uint idx = atomicCounterIncrement(u_CulledSubdBufferCounter);

		if(idx < MAX_NUM_SUBDIVISIONS)
			u_CulledSubdBuffer[idx] = uvec2(primID, key);
    }
}
#endif

