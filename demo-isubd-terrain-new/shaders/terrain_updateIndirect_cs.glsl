/* terrain_updateIndirect_cs.glsl - public domain
    (created by Jonathan Dupuy and Cyril Crassin)

*/

#ifdef COMPUTE_SHADER
layout(binding = BINDING_SUBD_ATOMIC_COUNTER)
uniform atomic_uint u_SubdAtomicCounter;

//Just for reseting
layout(binding = BINDING_VISIBLE_SUBD_ATOMIC_COUNTER)
uniform atomic_uint u_VisibleSubdAtomicCounter;


layout(std430, binding = BUFFER_BINDING_INDIRECT_COMMAND)		//BUFFER_DISPATCH_INDIRECT
buffer IndirectCommandBuffer {
    uint u_IndirectCommand[8];
};

/**
 * This function is implemented to intel, AMD, and NVidia GPUs.
 */
uint atomicCounterExchangeImpl(atomic_uint c, uint data)
{
#if ATOMIC_COUNTER_EXCHANGE_ARB
    return atomicCounterExchangeARB(c, data);
#elif ATOMIC_COUNTER_EXCHANGE_AMD
    return atomicCounterExchange(c, data);
#else
#error please configure atomicCounterExchange for your platform
#endif
}

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main()
{
	#if UPDATE_INDIRECT_STRUCT
	// uint cnt = atomicCounter(u_SubdAtomicCounter) / 32 + 1;

	uint numSubdivisions = atomicCounter(u_SubdAtomicCounter);
	uint numSubdivisionsClamped = min(numSubdivisions, MAX_NUM_SUBDIVISIONS);

    uint cnt = numSubdivisionsClamped / UPDATE_INDIRECT_VALUE_DIVIDE + UPDATE_INDIRECT_VALUE_ADD;

    u_IndirectCommand[UPDATE_INDIRECT_OFFSET] = cnt;

    //Hack: Store counter value in the last reserved field of the draw/dispatch indirect structure
    u_IndirectCommand[7] = numSubdivisionsClamped;
	#endif

    //Reset atomic counters
	#if UPDATE_INDIRECT_RESET_SUBD_ATOMIC_COUNTER
    atomicCounterExchangeImpl(u_SubdAtomicCounter, 0);
	#endif

	#if UPDATE_INDIRECT_RESET_VISIBLE_SUBD_ATOMIC_COUNTER
    atomicCounterExchangeImpl(u_VisibleSubdAtomicCounter, 0);
	#endif
}
#endif
