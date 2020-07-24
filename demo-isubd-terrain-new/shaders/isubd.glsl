/* isubd.glsl - public domain implicit subdivision on the GPU
    (created by Jonathan Dupuy)
*/
uint parentKey(in uint key)
{
    return (key >> 1u);
}

void childrenKeys(in uint key, out uint children[2])
{
    children[0] = (key << 1u) | 0u;
    children[1] = (key << 1u) | 1u;
}

bool isRootKey(in uint key)
{
    return (key == 1u);
}

bool isLeafKey(in uint key)
{
    return findMSB(key) == 31;
}

bool isChildZeroKey(in uint key)
{
    return ((key & 1u) == 0u);
}

// barycentric interpolation
vec3 berp(in vec3 v[3], in vec2 u)
{
    return v[0] + u.x * (v[1] - v[0]) + u.y * (v[2] - v[0]);
}
vec4 berp(in vec4 v[3], in vec2 u)
{
    return v[0] + u.x * (v[1] - v[0]) + u.y * (v[2] - v[0]);
}

// get xform from bit value
mat3 bitToXform(in uint bit)
{
    float b = float(bit);
    float c = 1.0f - b;
    vec3 c1 = vec3(0.0f, c   , b   );
    vec3 c2 = vec3(0.5f, b   , 0.0f);
    vec3 c3 = vec3(0.5f, 0.0f, c   );

    return mat3(c1, c2, c3);
}

// Get xform from key via successive matrix multiplication (see 1.2.2 Implicit Representation)
// TODO:
//  - store intermediate transforms to avoid redundant matrix multiplications (?) --> would require a lot of storage...
mat3 keyToXform(in uint key)
{
    mat3 xf = mat3(1.0f);//, 0.f, 0.f, 0.f, 1.f, 0.f, 0.f, 0.f, 1.f);

    while(key > 1u)
	{
        xf *= bitToXform(key & 1u);
        key = key >> 1u;
    }

    return xf;
}

// Get xform from key as well as xform from parent key
mat3 keyToXform(in uint key, out mat3 xfp)
{
    // TODO: optimize (compute parent xform and then concatenate with child's)
    xfp = keyToXform(parentKey(key));
    return keyToXform(key);
}


// TODO:
// - compute only vec3 (.w is not needed)
// - compute auxiliary data (uv, normal, ...)

// Subdivision routine (vertex position only)
//
// key:		Key of the subtriangle
// v_in:	Coarse triangle containing the current subtriangle
// v_out:	Subtriangle vertices
void subd(in uint key, in vec3 v_in[3], out vec3 v_out[3])
{
    mat3 xf = keyToXform(key);
    mat3x3 v = xf * transpose(mat3x3(v_in[0], v_in[1], v_in[2]));

    v_out[0] = vec3(v[0][0], v[1][0], v[2][0]);
    v_out[1] = vec3(v[0][1], v[1][1], v[2][1]);
    v_out[2] = vec3(v[0][2], v[1][2], v[2][2]);
}

// Subdivision routine (vertex position only)
// also computes parent position
//
// key:		Key of the subtriangle
// v_in:	Coarse triangle containing the current subtriangle
// v_out:	Subtriangle vertices
// v_out_p: Subtriangle's parent vertices
void subd(in uint key, in vec3 v_in[3], out vec3 v_out[3], out vec3 v_out_p[3])
{
    mat3 xfp; mat3 xf = keyToXform(key, xfp);

	#if 0
    mat3x3 v  = xf  * transpose(mat3x3(v_in[0], v_in[1], v_in[2]));
    mat3x3 vp = xfp * transpose(mat3x3(v_in[0], v_in[1], v_in[2]));

    v_out[0] = vec3(v[0][0], v[1][0], v[2][0]);
    v_out[1] = vec3(v[0][1], v[1][1], v[2][1]);
    v_out[2] = vec3(v[0][2], v[1][2], v[2][2]);

    v_out_p[0] = vec3(vp[0][0], vp[1][0], vp[2][0]);
    v_out_p[1] = vec3(vp[0][1], vp[1][1], vp[2][1]);
    v_out_p[2] = vec3(vp[0][2], vp[1][2], vp[2][2]);
	#else
		#if 0
		mat3x3 v  = xf  * transpose(mat3x3(v_in[0].xyz, v_in[1].xyz, v_in[2].xyz));
		#else
		mat3x3 v = xf * mat3x3(
			v_in[0].x, v_in[1].x, v_in[2].x, // 1st column
			v_in[0].y, v_in[1].y, v_in[2].y, // 2nd column x
			v_in[0].z, v_in[1].z, v_in[2].z  // 3rd column
		);
		#endif

		#if 0
			v_out[0] = vec3(v[0][0], v[1][0], v[2][0]);
			v_out[1] = vec3(v[0][1], v[1][1], v[2][1]);
			v_out[2] = vec3(v[0][2], v[1][2], v[2][2]);
		#else
			for(uint i = 0; i < 3u; ++i)
			{
				v_out[i] = vec3(
					xf[0][i] * v_in[0].x + xf[1][i] * v_in[1].x + xf[2][i] * v_in[2].x,
					xf[0][i] * v_in[0].y + xf[1][i] * v_in[1].y + xf[2][i] * v_in[2].y,
					xf[0][i] * v_in[0].z + xf[1][i] * v_in[1].z + xf[2][i] * v_in[2].z
				);
			}
		#endif

			
		mat3x3 vp = xfp * transpose(mat3x3(v_in[0], v_in[1], v_in[2]));
		v_out_p[0] = vec3(vp[0][0], vp[1][0], vp[2][0]);
		v_out_p[1] = vec3(vp[0][1], vp[1][1], vp[2][1]);
		v_out_p[2] = vec3(vp[0][2], vp[1][2], vp[2][2]);

		#if 0
			vec2 u1 = (xf * vec3(0, 0, 1)).xy;
			vec2 u2 = (xf * vec3(1, 0, 1)).xy;
			vec2 u3 = (xf * vec3(0, 1, 1)).xy;
			v_out[0] = berp(v_in, u1);
			v_out[1] = berp(v_in, u2);
			v_out[2] = berp(v_in, u3);

			vec2 u1_p = (xfp * vec3(0, 0, 1)).xy;
			vec2 u2_p = (xfp * vec3(1, 0, 1)).xy;
			vec2 u3_p = (xfp * vec3(0, 1, 1)).xy;
			v_out_p[0] = berp(v_in, u1_p);
			v_out_p[1] = berp(v_in, u2_p);
			v_out_p[2] = berp(v_in, u3_p);

		#endif

	#endif
}
