<%def name="insertBaseKernels()">

## TODO: replace by intrinsincs if necessary

#ifndef mad24
#define mad24(x, y, z) ((x) * (y) + (z))
#endif

#ifndef mad
#define mad(x, y, z) ((x) * (y) + (z))
#endif

// integer multiplication
#ifndef mul24
#ifdef __mul24
#define mul24(x, y) __mul24(x, y)
#endif
#ifndef __mul24
#define mul24(x, y) ((x) * (y))
#endif
#endif

## %if cuda:
##     #define complex_exp(res, ang) ${"sincos" + ("f" if scalar == "float" else "")}(ang, &((res).y), &((res).x))
## %else:
##     %if fast_math and scalar == "float":
##     ## seems that there are no native_* functions for doubles in OpenCL at the moment
##     #define complex_exp(res, ang) (res).x = native_cos(ang); (res).y = native_sin(ang)
##     %else:
##     #define complex_exp(res, ang) (res).x = cos(ang); (res).y = sin(ang)
##     %endif
## %endif

#ifdef sincosf
#define complex_exp(res, ang) ${"sincos" + ("" if dtypes.is_double(basis.dtype) else "f")}(ang, &((res).y), &((res).x))
#endif
#ifndef sincosf
#define complex_exp(res, ang) (res).x = cos(ang); (res).y = sin(ang)
#endif

#define complex_ctr COMPLEX_CTR(${dtypes.ctype(basis.dtype)})
#define complex_mul(a, b) complex_ctr(mad(-(a).y, (b).y, (a).x * (b).x), mad((a).y, (b).x, (a).x * (b).y))
#define complex_div_scalar(a, b) complex_ctr((a).x / (b), (a).y / (b))
#define conj(a) complex_ctr((a).x, -(a).y)
#define conj_transp(a) complex_ctr(-(a).y, (a).x)
#define conj_transp_and_mul(a, b) complex_ctr(-(a).y * (b), (a).x * (b))

typedef ${dtypes.ctype(basis.dtype)} complex_t;
typedef ${dtypes.ctype(dtypes.real_for(basis.dtype))} real_t;


WITHIN_KERNEL void swap(complex_t *a, complex_t *b)
{
    complex_t c = *a;
    *a = *b;
    *b = c;
}

// shifts the sequence (a1, a2, a3, a4, a5) transforming it to
// (a5, a1, a2, a3, a4)
WITHIN_KERNEL void shift32(
    complex_t *a1, complex_t *a2, complex_t *a3, complex_t *a4, complex_t *a5)
{
    complex_t c1, c2;
    c1 = *a2;
    *a2 = *a1;
    c2 = *a3;
    *a3 = c1;
    c1 = *a4;
    *a4 = c2;
    c2 = *a5;
    *a5 = c1;
    *a1 = c2;
}

WITHIN_KERNEL void _fftKernel2(complex_t *a)
{
    complex_t c = a[0];
    a[0] = c + a[1];
    a[1] = c - a[1];
}
#define fftKernel2(a, direction) _fftKernel2(a)

WITHIN_KERNEL void _fftKernel2S(complex_t *d1, complex_t *d2)
{
    complex_t c = *d1;
    *d1 = c + *d2;
    *d2 = c - *d2;
}
#define fftKernel2S(d1, d2, direction) _fftKernel2S(d1, d2)

WITHIN_KERNEL void fftKernel4(complex_t *a, const int direction)
{
    fftKernel2S(a + 0, a + 2, direction);
    fftKernel2S(a + 1, a + 3, direction);
    fftKernel2S(a + 0, a + 1, direction);
    a[3] = conj_transp_and_mul(a[3], direction);
    fftKernel2S(a + 2, a + 3, direction);
    swap(a + 1, a + 2);
}

WITHIN_KERNEL void fftKernel4s(complex_t *a0, complex_t *a1,
    complex_t *a2, complex_t *a3, const int direction)
{
    fftKernel2S(a0, a2, direction);
    fftKernel2S(a1, a3, direction);
    fftKernel2S(a0, a1, direction);
    *a3 = conj_transp_and_mul(*a3, direction);
    fftKernel2S(a2, a3, direction);
    swap(a1, a2);
}

WITHIN_KERNEL void bitreverse8(complex_t *a)
{
    swap(a + 1, a + 4);
    swap(a + 3, a + 6);
}

WITHIN_KERNEL void fftKernel8(complex_t *a, const int direction)
{
    const complex_t w1  = complex_ctr(
        ${wrap_const(numpy.sin(numpy.pi / 4))},
        ${wrap_const(numpy.sin(numpy.pi / 4))} * direction);
    const complex_t w3  = complex_ctr(
        ${wrap_const(-numpy.sin(numpy.pi / 4))},
        ${wrap_const(numpy.sin(numpy.pi / 4))} * direction);
    fftKernel2S(a + 0, a + 4, direction);
    fftKernel2S(a + 1, a + 5, direction);
    fftKernel2S(a + 2, a + 6, direction);
    fftKernel2S(a + 3, a + 7, direction);
    a[5] = complex_mul(w1, a[5]);
    a[6] = conj_transp_and_mul(a[6], direction);
    a[7] = complex_mul(w3, a[7]);
    fftKernel2S(a + 0, a + 2, direction);
    fftKernel2S(a + 1, a + 3, direction);
    fftKernel2S(a + 4, a + 6, direction);
    fftKernel2S(a + 5, a + 7, direction);
    a[3] = conj_transp_and_mul(a[3], direction);
    a[7] = conj_transp_and_mul(a[7], direction);
    fftKernel2S(a + 0, a + 1, direction);
    fftKernel2S(a + 2, a + 3, direction);
    fftKernel2S(a + 4, a + 5, direction);
    fftKernel2S(a + 6, a + 7, direction);
    bitreverse8(a);
}

WITHIN_KERNEL void bitreverse4x4(complex_t *a)
{
    swap(a + 1, a + 4);
    swap(a + 2, a + 8);
    swap(a + 3, a + 12);
    swap(a + 6, a + 9);
    swap(a + 7, a + 13);
    swap(a + 11, a + 14);
}

WITHIN_KERNEL void fftKernel16(complex_t *a, const int direction)
{
    complex_t temp;
    const real_t w0 = ${wrap_const(numpy.cos(numpy.pi / 8))};
    const real_t w1 = ${wrap_const(numpy.sin(numpy.pi / 8))};
    const real_t w2 = ${wrap_const(numpy.sin(numpy.pi / 4))};
    fftKernel4s(a + 0, a + 4, a + 8,  a + 12, direction);
    fftKernel4s(a + 1, a + 5, a + 9,  a + 13, direction);
    fftKernel4s(a + 2, a + 6, a + 10, a + 14, direction);
    fftKernel4s(a + 3, a + 7, a + 11, a + 15, direction);

    temp  = complex_ctr(w0, direction * w1);
    a[5]  = complex_mul(a[5], temp);
    temp  = complex_ctr(w1, direction * w0);
    a[7]  = complex_mul(a[7], temp);
    temp  = complex_ctr(w2, direction * w2);
    a[6]  = complex_mul(a[6], temp);
    a[9]  = complex_mul(a[9], temp);

    a[10] = conj_transp_and_mul(a[10], direction);

    temp  = complex_ctr(-w2, direction * w2);
    a[11] = complex_mul(a[11], temp);
    a[14] = complex_mul(a[14], temp);
    temp  = complex_ctr(w1, direction * w0);
    a[13] = complex_mul(a[13], temp);
    temp  = complex_ctr(-w0, -direction * w1);
    a[15] = complex_mul(a[15], temp);

    fftKernel4(a, direction);
    fftKernel4(a + 4, direction);
    fftKernel4(a + 8, direction);
    fftKernel4(a + 12, direction);
    bitreverse4x4(a);
}

WITHIN_KERNEL void bitreverse32(complex_t *a)
{
    shift32(a + 1, a + 2, a + 4, a + 8, a + 16);
    shift32(a + 3, a + 6, a + 12, a + 24, a + 17);
    shift32(a + 5, a + 10, a + 20, a + 9, a + 18);
    shift32(a + 7, a + 14, a + 28, a + 25, a + 19);
    shift32(a + 11, a + 22, a + 13, a + 26, a + 21);
    shift32(a + 15, a + 30, a + 29, a + 27, a + 23);
}

WITHIN_KERNEL void fftKernel32(complex_t *a, const int direction)
{
    complex_t temp;
    %for i in range(16):
        fftKernel2S(a + ${i}, a + ${i + 16}, direction);
    %endfor

    %for i in range(1, 16):
        temp = complex_ctr(
            ${wrap_const(numpy.cos(i * numpy.pi / 16))},
            ${wrap_const(numpy.sin(i * numpy.pi / 16))}
        );
        a[${i + 16}] = complex_mul(a[${i + 16}], temp);
    %endfor

    fftKernel16(a, direction);
    fftKernel16(a + 16, direction);
    bitreverse32(a);
}

</%def>

<%def name="insertGlobalLoad(input, a_index, g_index)">
    a[${a_index}] = ${input.load}(${g_index} + input_shift);
</%def>

<%def name="insertGlobalStore(output, a_index, g_index)">
    ${output.store}(${g_index} + output_shift, complex_div_scalar(a[${a_index}], norm_coeff));
</%def>

<%def name="insertGlobalLoadsAndTranspose(input, n, threads_per_xform, xforms_per_block, radix, mem_coalesce_width)">

    <%
        log2_threads_per_xform = log2(threads_per_xform)
        block_size = threads_per_xform * xforms_per_block
    %>

    %if xforms_per_block > 1:
        s = ${global_batch} & ${xforms_per_block - 1};
    %endif

    %if threads_per_xform >= mem_coalesce_width:
        %if xforms_per_block > 1:
            ii = thread_id & ${threads_per_xform - 1};
            jj = thread_id >> ${log2_threads_per_xform};

            if(!s || (block_id < blocks_num - 1) || (jj < s))
            {
                {
                    int offset = mad24(mad24(block_id, ${xforms_per_block}, jj), ${n}, ii);
                    input_shift += offset;
                    output_shift += offset;
                }

            %for i in range(radix):
                ${insertGlobalLoad(input, i, i * threads_per_xform)}
            %endfor
            }
        %else:
            ii = thread_id;

            {
                int offset = mad24(block_id, ${n}, ii);
                input_shift += offset;
                output_shift += offset;
            }

            %for i in range(radix):
                ${insertGlobalLoad(input, i, i * threads_per_xform)}
            %endfor
        %endif

    %elif n >= mem_coalesce_width:
        <%
            num_inner_iter = n / mem_coalesce_width
            num_outer_iter = xforms_per_block / (block_size / mem_coalesce_width)
        %>

        ii = thread_id & ${mem_coalesce_width - 1};
        jj = thread_id >> ${log2(mem_coalesce_width)};
        smem_store_index = mad24(jj, ${n + threads_per_xform}, ii);

        {
            int offset = mad24(block_id, ${xforms_per_block}, jj);
            offset = mad24(offset, ${n}, ii);
            input_shift += offset;
            output_shift += offset;
        }

        if((block_id == blocks_num - 1) && s)
        {
        %for i in range(num_outer_iter):
            if(jj < s)
            {
            %for j in range(num_inner_iter):
                ${insertGlobalLoad(input, i * num_inner_iter + j, \
                    j * mem_coalesce_width + i * (block_size / mem_coalesce_width) * n)}
            %endfor
            }
            %if i != num_outer_iter - 1:
                jj += ${block_size / mem_coalesce_width};
            %endif
        %endfor
        }
        else
        {
        %for i in range(num_outer_iter):
            %for j in range(num_inner_iter):
                ${insertGlobalLoad(input, i * num_inner_iter + j, \
                    j * mem_coalesce_width + i * (block_size / mem_coalesce_width) * n)}
            %endfor
        %endfor
        }

        ii = thread_id & ${threads_per_xform - 1};
        jj = thread_id >> ${log2_threads_per_xform};
        smem_load_index = mad24(jj, ${n + threads_per_xform}, ii);

        %for comp in ('x', 'y'):
            %for i in range(num_outer_iter):
                %for j in range(num_inner_iter):
                    smem[smem_store_index + ${j * mem_coalesce_width + \
                        i * (block_size / mem_coalesce_width) * (n + threads_per_xform)}] =
                        a[${i * num_inner_iter + j}].${comp};
                %endfor
            %endfor
            LOCAL_BARRIER;

            %for i in range(radix):
                a[${i}].${comp} = smem[smem_load_index + ${i * threads_per_xform}];
            %endfor
            LOCAL_BARRIER;
        %endfor
    %else:
        {
            int offset = mad24(block_id, ${n * xforms_per_block}, thread_id);
            input_shift += offset;
            output_shift += offset;
        }

        ii = thread_id & ${n - 1};
        jj = thread_id >> ${log2(n)};
        smem_store_index = mad24(jj, ${n + threads_per_xform}, ii);

        if((block_id == blocks_num - 1) && s)
        {
        %for i in range(radix):
            if(jj < s)
            {
                ${insertGlobalLoad(input, i, i * block_size)}
            }
            %if i != radix - 1:
                jj += ${block_size / n};
            %endif
        %endfor
        }
        else
        {
        %for i in range(radix):
            ${insertGlobalLoad(input, i, i*block_size)}
        %endfor
        }

        %if threads_per_xform > 1:
            ii = thread_id & ${threads_per_xform - 1};
            jj = thread_id >> ${log2_threads_per_xform};
            smem_load_index = mad24(jj, ${n + threads_per_xform}, ii);
        %else:
            ii = 0;
            jj = thread_id;
            smem_load_index = mul24(jj, ${n + threads_per_xform});
        %endif

        %for comp in ('x', 'y'):
            %for i in range(radix):
                smem[smem_store_index + ${i * (block_size / n) * (n + threads_per_xform)}] = a[${i}].${comp};
            %endfor
            LOCAL_BARRIER;

            %for i in range(radix):
                a[${i}].${comp} = smem[smem_load_index + ${i * threads_per_xform}];
            %endfor
            LOCAL_BARRIER;
        %endfor
    %endif
</%def>

<%def name="insertGlobalStoresAndTranspose(output, n, max_radix, radix, threads_per_xform, xforms_per_block, mem_coalesce_width)">

    <%
        block_size = threads_per_xform * xforms_per_block
        num_iter = max_radix / radix
    %>

    %if threads_per_xform >= mem_coalesce_width:
        %if xforms_per_block > 1:
            if(!s || (block_id < blocks_num - 1) || (jj < s))
            {
        %endif

        %for i in range(max_radix):
            <%
                j = i % num_iter
                k = i / num_iter
                ind = j * radix + k
            %>
            ${insertGlobalStore(output, ind, i * threads_per_xform)}
        %endfor

        %if xforms_per_block > 1:
            }
        %endif

    %elif n >= mem_coalesce_width:
        <%
            num_inner_iter = n / mem_coalesce_width
            num_outer_iter = xforms_per_block / (block_size / mem_coalesce_width)
        %>
        smem_load_index  = mad24(jj, ${n + threads_per_xform}, ii);
        ii = thread_id & ${mem_coalesce_width - 1};
        jj = thread_id >> ${log2(mem_coalesce_width)};
        smem_store_index = mad24(jj, ${n + threads_per_xform}, ii);

        %for comp in ('x', 'y'):
            %for i in range(max_radix):
                <%
                    j = i % num_iter
                    k = i / num_iter
                    ind = j * radix + k
                %>
                smem[smem_load_index + ${i * threads_per_xform}] = a[${ind}].${comp};
            %endfor
            LOCAL_BARRIER;

            %for i in range(num_outer_iter):
                %for j in range(num_inner_iter):
                    a[${i*num_inner_iter + j}].${comp} = smem[smem_store_index + ${j * mem_coalesce_width + \
                        i * (block_size / mem_coalesce_width) * (n + threads_per_xform)}];
                %endfor
            %endfor
            LOCAL_BARRIER;
        %endfor

        if((block_id == blocks_num - 1) && s)
        {
        %for i in range(num_outer_iter):
            if(jj < s)
            {
            %for j in range(num_inner_iter):
                ${insertGlobalStore(output, i * num_inner_iter + j, \
                    j * mem_coalesce_width + i * (block_size / mem_coalesce_width) * n)}
            %endfor
            }
            %if i != num_outer_iter - 1:
                jj += ${block_size / mem_coalesce_width};
            %endif
        %endfor
        }
        else
        {
        %for i in range(num_outer_iter):
            %for j in range(num_inner_iter):
                ${insertGlobalStore(output, i * num_inner_iter + j, \
                    j * mem_coalesce_width + i * (block_size / mem_coalesce_width) * n)}
            %endfor
        %endfor
        }
    %else:
        smem_load_index = mad24(jj, ${n + threads_per_xform}, ii);
        ii = thread_id & ${n - 1};
        jj = thread_id >> ${log2(n)};
        smem_store_index = mad24(jj, ${n + threads_per_xform}, ii);

        %for comp in ('x', 'y'):
            %for i in range(max_radix):
                <%
                    j = i % num_iter
                    k = i / num_iter
                    ind = j * radix + k
                %>
                smem[smem_load_index + ${i * threads_per_xform}] = a[${ind}].${comp};
            %endfor
            LOCAL_BARRIER;

            %for i in range(max_radix):
                a[${i}].${comp} = smem[smem_store_index + ${i * (block_size / n) * (n + threads_per_xform)}];
            %endfor
            LOCAL_BARRIER;
        %endfor

        if((block_id == blocks_num - 1) && s)
        {
        %for i in range(max_radix):
            if(jj < s)
            {
                ${insertGlobalStore(output, i, i * block_size)}
            }
            %if i != max_radix - 1:
                jj += ${block_size / n};
            %endif
        %endfor
        }
        else
        {
            %for i in range(max_radix):
                ${insertGlobalStore(output, i, i * block_size)}
            %endfor
        }
    %endif
</%def>

<%def name="insertTwiddleKernel(radix, num_iter, radix_prev, data_len, threads_per_xform)">

    <% log2_radix_prev = log2(radix_prev) %>
    {
        // Twiddle kernel
        real_t angf, ang;
        complex_t w;

    %for z in range(num_iter):
        %if z == 0:
            %if radix_prev > 1:
                angf = (real_t)(ii >> ${log2_radix_prev});
            %else:
                angf = (real_t)ii;
            %endif
        %else:
            %if radix_prev > 1:
                angf = (real_t)((${z * threads_per_xform} + ii) >> ${log2_radix_prev});
            %else:
                ## TODO: find out which conditions are necessary to execute this code
                angf = (real_t)(${z * threads_per_xform} + ii);
            %endif
        %endif

        %for k in range(1, radix):
            <% ind = z * radix + k %>
            ang = ${wrap_const(2 * numpy.pi * k / data_len)} * angf * direction;
            complex_exp(w, ang);
            a[${ind}] = complex_mul(a[${ind}], w);
        %endfor
    %endfor
    }
</%def>

<%def name="insertLocalStores(num_iter, radix, threads_per_xform, threads_req, offset, comp)">
    %for z in range(num_iter):
        %for k in range(radix):
            <% index = k * (threads_req + offset) + z * threads_per_xform %>
            smem[smem_store_index + ${index}] = a[${z * radix + k}].${comp};
        %endfor
    %endfor
    LOCAL_BARRIER;
</%def>

<%def name="insertLocalLoads(n, radix, radix_next, radix_prev, radix_curr, threads_per_xform, threads_req, offset, comp)">
    <%
        threads_req_next = n / radix_next
        inter_block_hnum = max(radix_prev / threads_per_xform, 1)
        inter_block_hstride = threads_per_xform
        vert_width = max(threads_per_xform / radix_prev, 1)
        vert_width = min(vert_width, radix)
        vert_num = radix / vert_width
        vert_stride = (n / radix + offset) * vert_width
        iter = max(threads_req_next / threads_per_xform, 1)
        intra_block_hstride = max(threads_per_xform / (radix_prev * radix), 1)
        intra_block_hstride *= radix_prev

        stride = threads_req / radix_next
    %>

    %for i in range(iter):
        <%
            ii = i / (inter_block_hnum * vert_num)
            zz = i % (inter_block_hnum * vert_num)
            jj = zz % inter_block_hnum
            kk = zz / inter_block_hnum
        %>

        %for z in range(radix_next):
            <% st = kk * vert_stride + jj * inter_block_hstride + ii * intra_block_hstride + z * stride %>
            a[${i * radix_next + z}].${comp} = smem[smem_load_index + ${st}];
        %endfor
    %endfor
    LOCAL_BARRIER;
</%def>

<%def name="insertLocalLoadIndexArithmetic(radix_prev, radix, threads_req, threads_per_xform, xforms_per_block, offset, mid_pad)">
    <%
        radix_curr = radix_prev * radix
        log2_radix_curr = log2(radix_curr)
        log2_radix_prev = log2(radix_prev)
        incr = (threads_req + offset) * radix + mid_pad
    %>

    %if radix_curr < threads_per_xform:
        %if radix_prev == 1:
            j = ii & ${radix_curr - 1};
        %else:
            j = (ii & ${radix_curr - 1}) >> ${log2_radix_prev};
        %endif

        %if radix_prev == 1:
            i = ii >> ${log2_radix_curr};
        %else:
            i = mad24(ii >> ${log2_radix_curr}, ${radix_prev}, ii & ${radix_prev - 1});
        %endif
    %else:
        %if radix_prev == 1:
            j = ii;
        %else:
            j = ii >> ${log2_radix_prev};
        %endif

        %if radix_prev == 1:
            i = 0;
        %else:
            i = ii & ${radix_prev - 1};
        %endif
    %endif

    %if xforms_per_block > 1:
        i = mad24(jj, ${incr}, i);
    %endif

    smem_load_index = mad24(j, ${threads_req + offset}, i);
</%def>

<%def name="insertLocalStoreIndexArithmetic(threads_req, xforms_per_block, radix, offset, mid_pad)">
    %if xforms_per_block == 1:
        smem_store_index = ii;
    %else:
        smem_store_index = mad24(jj, ${(threads_req + offset) * radix + mid_pad}, ii);
    %endif
</%def>

<%def name="insertVariableDefinitions(direction, shared_mem, temp_array_size)">

    %if shared_mem > 0:
        LOCAL_MEM real_t smem[${shared_mem}];
        size_t smem_store_index, smem_load_index;
    %endif

    complex_t a[${temp_array_size}];

    int input_shift = 0;
    int output_shift = 0;

    int thread_id = get_local_id(0);
    int block_id = get_group_id(0);

    ## makes it easier to use it inside other definitions
    int direction = ${direction};

    int norm_coeff = direction == 1 ? ${norm_coeff if normalize else 1} : 1;
</%def>

<%def name="fft_local(output, input, direction)">

    <%
        max_radix = radix_arr[0]
        num_radix = len(radix_arr)
    %>

${insertBaseKernels()}

${kernel_definition}
{
    VIRTUAL_SKIP_THREADS;

    ${insertVariableDefinitions(direction, shared_mem, max_radix)}
    int ii;
    %if num_radix > 1:
        int i, j;
    %endif

    %if not (threads_per_xform >= min_mem_coalesce_width and xforms_per_block == 1):
        int jj, s;
        %if cuda:
            int blocks_num = gridDim.x * gridDim.y;
        %else:
            int blocks_num = get_num_groups(0);
        %endif
    %endif

    ${insertGlobalLoadsAndTranspose(input, n, threads_per_xform, xforms_per_block, max_radix,
        min_mem_coalesce_width)}

    <%
        radix_prev = 1
        data_len = n
    %>

    %for r in range(num_radix):
        <%
            num_iter = radix_arr[0] / radix_arr[r]
            threads_req = n / radix_arr[r]
            radix_curr = radix_prev * radix_arr[r]
        %>

        %for i in range(num_iter):
            fftKernel${radix_arr[r]}(a + ${i * radix_arr[r]}, direction);
        %endfor

        %if r < num_radix - 1:
            ${insertTwiddleKernel(radix_arr[r], num_iter, radix_prev, data_len, threads_per_xform)}
            <%
                lMemSize, offset, mid_pad = getPadding(threads_per_xform, radix_prev, threads_req,
                    xforms_per_block, radix_arr[r], num_smem_banks)
            %>
            ${insertLocalStoreIndexArithmetic(threads_req, xforms_per_block, radix_arr[r], offset, mid_pad)}
            ${insertLocalLoadIndexArithmetic(radix_prev, radix_arr[r], threads_req, threads_per_xform, xforms_per_block, offset, mid_pad)}
            %for comp in ('x', 'y'):
                ${insertLocalStores(num_iter, radix_arr[r], threads_per_xform, threads_req, offset, comp)}
                ${insertLocalLoads(n, radix_arr[r], radix_arr[r+1], radix_prev, radix_curr, threads_per_xform, threads_req, offset, comp)}
            %endfor
            <%
                radix_prev = radix_curr
                data_len = data_len / radix_arr[r]
            %>
        %endif
    %endfor

    ${insertGlobalStoresAndTranspose(output, n, max_radix, radix_arr[num_radix - 1], threads_per_xform,
        xforms_per_block, min_mem_coalesce_width)}
}

</%def>

<%def name="fft_global(output, input, direction)">

${insertBaseKernels()}

    <%
        radix_arr, radix1_arr, radix2_arr = getGlobalRadixInfo(n)

        num_passes = len(radix_arr)

        radix_init = horiz_bs if vertical else 1

        radix = radix_arr[pass_num]
        radix1 = radix1_arr[pass_num]
        radix2 = radix2_arr[pass_num]

        stride_in = radix_init
        for i in range(num_passes):
            if i != pass_num:
                stride_in *= radix_arr[i]

        stride_out = radix_init
        for i in range(pass_num):
            stride_out *= radix_arr[i]

        block_size = min(batch_size * radix2, max_block_size)

        num_iter = radix1 / radix2
        input_multiplier = block_size / batch_size
        log2_stride_out = log2(stride_out)
        blocks_per_xform = stride_in / batch_size

        m = log2(n)
    %>

${kernel_definition}
{
    VIRTUAL_SKIP_THREADS;

    ${insertVariableDefinitions(direction, shared_mem, radix1)}
    int index_in, index_out, x_num, tid, i, j;
    %if not vertical or pass_num < num_passes - 1:
        int b_num;
    %endif

    <%
        log2_blocks_per_xform = log2(blocks_per_xform)
    %>

    %if vertical:
        x_num = block_id >> ${log2_blocks_per_xform};
        block_id = block_id & ${blocks_per_xform - 1};
        index_in = mad24(block_id, ${batch_size}, x_num << ${log2(n * horiz_bs)});
        tid = mul24(block_id, ${batch_size});
        i = tid >> ${log2_stride_out};
        j = tid & ${stride_out - 1};
        <%
            stride = radix * radix_init
            for i in range(pass_num):
                stride *= radix_arr[i]
        %>
        index_out = mad24(i, ${stride}, j + (x_num << ${log2(n*horiz_bs)}));

        ## do not set it, if it won't be used
        %if pass_num < num_passes - 1:
            b_num = block_id;
        %endif
    %else:
        b_num = block_id & ${blocks_per_xform - 1};
        x_num = block_id >> ${log2_blocks_per_xform};
        index_in = mul24(b_num, ${batch_size});
        tid = index_in;
        i = tid >> ${log2_stride_out};
        j = tid & ${stride_out - 1};
        <%
            stride = radix*radix_init
            for i in range(pass_num):
                stride *= radix_arr[i]
        %>
        index_out = mad24(i, ${stride}, j);
        index_in += (x_num << ${m});
        index_out += (x_num << ${m});
    %endif

    ## Load Data
    <% log2_batch_size = log2(batch_size) %>
    tid = thread_id;
    i = tid & ${batch_size - 1};
    j = tid >> ${log2_batch_size};
    index_in += mad24(j, ${stride_in}, i);

    input_shift += index_in;
    %for j in range(radix1):
        a[${j}] = ${input.load}(${j * input_multiplier * stride_in} + input_shift);
    %endfor

    fftKernel${radix1}(a, direction);

    %if radix2 > 1:
        ## twiddle
        {
            real_t ang;
            complex_t w;

        %for k in range(1, radix1):
            ## TODO: for some reason, writing it in form
            ## (real_t)${2 * numpy.pi / radix} * (real_t)${k} gives slightly better precision
            ## have to try it with double precision
            ang = ${wrap_const(2 * numpy.pi * k / radix)} * j * direction;
            complex_exp(w, ang);
            a[${k}] = complex_mul(a[${k}], w);
        %endfor
        }

        ## shuffle
        index_in = mad24(j, ${block_size * num_iter}, i);
        smem_store_index = tid;
        smem_load_index = index_in;

        %for comp in ('x', 'y'):
            %for k in range(radix1):
                smem[smem_store_index + ${k * block_size}] = a[${k}].${comp};
            %endfor
            LOCAL_BARRIER;

            %for k in range(num_iter):
                %for t in range(radix2):
                    a[${k * radix2 + t}].${comp} = smem[smem_load_index + ${t * batch_size + k * block_size}];
                %endfor
            %endfor
            LOCAL_BARRIER;
        %endfor

        %for j in range(num_iter):
            fftKernel${radix2}(a + ${j * radix2}, direction);
        %endfor
    %endif

    ## twiddle
    %if pass_num < num_passes - 1:
    {
        real_t ang1, ang;
        complex_t w;

        int l = ((b_num << ${log2_batch_size}) + i) >> ${log2_stride_out};
        int k = j << ${log2(radix1 / radix2)};
        ang1 = ${wrap_const(2 * numpy.pi / curr_n)} * l * direction;
        %for t in range(radix1):
            ang = ang1 * (k + ${(t % radix2) * radix1 + (t / radix2)});
            complex_exp(w, ang);
            a[${t}] = complex_mul(a[${t}], w);
        %endfor
    }
    %endif

    ## Store Data
    %if stride_out == 1:
        smem_store_index = mad24(i, ${radix + 1}, j << ${log2(radix1 / radix2)});
        smem_load_index = mad24(tid >> ${log2(radix)}, ${radix + 1}, tid & ${radix - 1});

        %for comp in ('x', 'y'):
            %for i in range(radix1 / radix2):
                %for j in range(radix2):
                    smem[smem_store_index + ${i + j * radix1}] = a[${i * radix2 + j}].${comp};
                %endfor
            %endfor
            LOCAL_BARRIER;

            %if block_size >= radix:
                %for i in range(radix1):
                    a[${i}].${comp} = smem[smem_load_index + ${i * (radix + 1) * (block_size / radix)}];
                %endfor
            %else:
                <%
                    inner_iter = radix / block_size
                    outer_iter = radix1 / inner_iter
                %>
                %for i in range(outer_iter):
                    %for j in range(inner_iter):
                        a[${i * inner_iter + j}].${comp} = smem[smem_load_index + ${j * block_size + i * (radix + 1)}];
                    %endfor
                %endfor
            %endif
            LOCAL_BARRIER;
        %endfor

        index_out += tid;

        output_shift += index_out;
        %for k in range(radix1):
            ${output.store}(${k * block_size} + output_shift,
                complex_div_scalar(a[${k}], norm_coeff));
        %endfor
    %else:
        index_out += mad24(j, ${num_iter * stride_out}, i);

        output_shift += index_out;
        %for k in range(radix1):
            ${output.store}(${((k % radix2) * radix1 + (k / radix2)) * stride_out} + output_shift,
                complex_div_scalar(a[${k}], norm_coeff));
        %endfor
    %endif
}

</%def>