//! Shared Pass 5 test fixtures (inline to avoid @embedFile path restrictions).
pub const point_h =
    \\#ifndef DUO_PASS5_POINT_H
    \\#define DUO_PASS5_POINT_H
    \\
    \\typedef struct {
    \\    double x;
    \\    double y;
    \\} CPoint;
    \\
    \\double distance2(CPoint point);
    \\
    \\#endif
    ;

pub const big_rect_h =
    \\#ifndef DUO_PASS5_BIG_RECT_H
    \\#define DUO_PASS5_BIG_RECT_H
    \\
    \\typedef struct {
    \\    double a;
    \\    double b;
    \\    double c;
    \\    double d;
    \\} CBigRect;
    \\
    \\double sum4(CBigRect *rect);
    \\
    \\#endif
    ;
