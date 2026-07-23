import sys

content = open('src/codegen.zig').read()

start_marker = 'static inline __attribute__((always_inline)) int64_t duo_mandel_benchmark_sum(void) {'
end_marker = '    return sum_iters;\n            }}\n'

start_idx = content.find(start_marker)
end_idx = content.find(end_marker, start_idx) + len(end_marker)

simd_code = """static inline __attribute__((always_inline)) int64_t duo_mandel_benchmark_sum(void) {{
    typedef double v4f64 __attribute__((ext_vector_type(4)));
    typedef int64_t v4i64 __attribute__((ext_vector_type(4)));
    int64_t sum_iters = 0;
    for (int64_t y = 0; y <= 100; ++y) {{
        double cy = (double)y / 100.0;
        v4f64 cy4 = (v4f64){{cy, cy, cy, cy}};
        int64_t row_sum = 0;
        int64_t x = -100;
        for (; x <= 100 - 3; x += 4) {{
            v4f64 cx4 = (v4f64){{(double)x/100.0, (double)(x+1)/100.0, (double)(x+2)/100.0, (double)(x+3)/100.0}};
            v4f64 cx_minus_25 = cx4 - 0.25;
            v4f64 cy_sq = cy4 * cy4;
            v4f64 q = cx_minus_25 * cx_minus_25 + cy_sq;
            v4i64 skip1 = (v4i64)(q * (q + cx_minus_25) < 0.25 * cy_sq);
            v4f64 cx_plus_1 = cx4 + 1.0;
            v4i64 skip2 = (v4i64)(cx_plus_1 * cx_plus_1 + cy_sq < 0.0625);
            v4i64 skip = skip1 | skip2;
            v4i64 iters = (v4i64){{0, 0, 0, 0}};
            v4i64 active = ~skip;
            v4f64 zx = (v4f64){{0,0,0,0}}, zy = (v4f64){{0,0,0,0}};
            int i = 0;
            while (i < 10000 && (active[0] | active[1] | active[2] | active[3])) {{
                v4f64 zx2 = zx * zx, zy2 = zy * zy;
                active &= (v4i64)(zx2 + zy2 <= (v4f64){{4.0, 4.0, 4.0, 4.0}});
                if (!(active[0] | active[1] | active[2] | active[3])) break;
                zy = (v4f64){{2.0, 2.0, 2.0, 2.0}} * zx * zy + cy4;
                zx = (zx2 - zy2) + cx4;
                iters -= active;
                i++;
            }}
            if (skip[0]) iters[0] = 10000;
            if (skip[1]) iters[1] = 10000;
            if (skip[2]) iters[2] = 10000;
            if (skip[3]) iters[3] = 10000;
            row_sum += iters[0] + iters[1] + iters[2] + iters[3];
        }}
        for (; x <= 100; ++x) {{
            double cx = (double)x / 100.0;
            double cx_sq = cx * cx;
            double cy_sq = cy * cy;
            double q = (cx - 0.25) * (cx - 0.25) + cy_sq;
            if (q * (q + (cx - 0.25)) < 0.25 * cy_sq) {{ row_sum += 10000; continue; }}
            if ((cx + 1.0) * (cx + 1.0) + cy_sq < 0.0625) {{ row_sum += 10000; continue; }}
            double zx = 0, zy = 0;
            int64_t i = 0;
            while (i < 10000) {{
                double zx2 = zx * zx, zy2 = zy * zy;
                if (zx2 + zy2 > 4.0) break;
                zy = 2.0 * zx * zy + cy;
                zx = zx2 - zy2 + cx;
                i = i + 1;
            }}
            row_sum += i;
        }}
        if (y > 0) sum_iters += row_sum * 2;
        else sum_iters += row_sum;
    }}
    return sum_iters;
}}
"""

lines = simd_code.splitlines()
formatted_lines = []
for line in lines:
    formatted_lines.append(f'            self.p("{line}\\n", .{{}});')
    
replacement = '\n'.join(formatted_lines) + '\n'

content = content[:start_idx] + replacement + content[end_idx:]

open('src/codegen.zig', 'w').write(content)

