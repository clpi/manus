| field | value |
|---|---|
| title | Benchmark results |

| # | directive |
|---|---|
| 1 | Generated 2026-09-12T21:48:24 by `bench/run.sh` (21 interleaved rounds, 3 warmup, median is primary). |

| # | directive |
|---|---|
| 1 | Honesty policy: every program x every compiler is listed. |
| 2 | Losses are reported, not hidden. |
| 3 | A loss is a bug report against the compiler. |

| section |
|---|---|
| sum |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001672 | 0.001679 | 0.000101 | 0.001486 | 0.001864 | 0.001822 | 0 |
| clang | 0.001680 | 0.001698 | 0.000125 | 0.001499 | 0.001918 | 0.001901 | 0 |
| gcc | 0.001631 | 0.001688 | 0.000143 | 0.001489 | 0.002120 | 0.001882 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -2.45%, p=0.8223 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.026s, clang 0.036s, gcc 0.040s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 295, clang 512, gcc 512. |

| section |
|---|---|
| arith |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.041194 | 0.041474 | 0.001054 | 0.040285 | 0.044225 | 0.043823 | 0 |
| clang | 0.041322 | 0.041477 | 0.001354 | 0.040258 | 0.046316 | 0.043413 | 1 |
| gcc | 0.040760 | 0.041261 | 0.001271 | 0.040163 | 0.045210 | 0.043414 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -1.07%, p=0.5639 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.025s, clang 0.037s, gcc 0.042s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 295, clang 544, gcc 544. |

| section |
|---|---|
| fib |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001625 | 0.001636 | 0.000104 | 0.001452 | 0.001837 | 0.001786 | 0 |
| clang | 0.001616 | 0.001649 | 0.000109 | 0.001426 | 0.001942 | 0.001809 | 0 |
| gcc | 0.001673 | 0.001690 | 0.000146 | 0.001498 | 0.002085 | 0.001958 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -0.54%, p=0.7099 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.023s, clang 0.036s, gcc 0.040s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 323, clang 512, gcc 512. |

| section |
|---|---|
| nest |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001643 | 0.001866 | 0.000771 | 0.001473 | 0.004487 | 0.003957 | 2 |
| clang | 0.001632 | 0.001857 | 0.000604 | 0.001520 | 0.003822 | 0.003450 | 3 |
| gcc | 0.001621 | 0.001817 | 0.000616 | 0.001545 | 0.003903 | 0.003494 | 2 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -1.38%, p=0.8220 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.027s, clang 0.041s, gcc 0.047s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 275, clang 512, gcc 512. |

| section |
|---|---|
| div |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.033153 | 0.033549 | 0.001110 | 0.032476 | 0.037310 | 0.035517 | 1 |
| clang | 0.033109 | 0.033373 | 0.000809 | 0.032612 | 0.035381 | 0.035240 | 2 |
| gcc | 0.033184 | 0.033506 | 0.000835 | 0.032584 | 0.036234 | 0.034874 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -0.13%, p=0.5665 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.026s, clang 0.040s, gcc 0.045s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 327, clang 560, gcc 560. |

| section |
|---|---|
| mul13 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.053567 | 0.054109 | 0.001488 | 0.052878 | 0.059062 | 0.057554 | 1 |
| clang | 0.053739 | 0.053874 | 0.000716 | 0.052922 | 0.055702 | 0.055126 | 0 |
| gcc | 0.054055 | 0.054133 | 0.000945 | 0.052737 | 0.056769 | 0.055794 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, margin +0.32%, p=0.5252 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.024s, clang 0.036s, gcc 0.045s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 295, clang 544, gcc 544. |

| section |
|---|---|
| bigconst |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001669 | 0.001686 | 0.000092 | 0.001527 | 0.001895 | 0.001825 | 0 |
| clang | 0.001686 | 0.001691 | 0.000137 | 0.001501 | 0.002034 | 0.001949 | 0 |
| gcc | 0.001673 | 0.001667 | 0.000109 | 0.001484 | 0.001952 | 0.001798 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): win, margin +0.23%, p=0.5501 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.023s, clang 0.035s, gcc 0.040s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 283, clang 512, gcc 512. |

| section |
|---|---|
| zerotrip |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001660 | 0.001697 | 0.000138 | 0.001414 | 0.002003 | 0.001967 | 0 |
| clang | 0.001662 | 0.001708 | 0.000285 | 0.001447 | 0.002894 | 0.001900 | 1 |
| gcc | 0.001680 | 0.001731 | 0.000319 | 0.001445 | 0.003033 | 0.002101 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, margin +0.15%, p=0.8757 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.023s, clang 0.037s, gcc 0.045s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 267, clang 512, gcc 512. |

| section |
|---|---|
| upbranch |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.008516 | 0.008528 | 0.000453 | 0.007815 | 0.009581 | 0.009323 | 0 |
| clang | 0.008222 | 0.008210 | 0.000408 | 0.007551 | 0.008880 | 0.008830 | 0 |
| gcc | 0.007987 | 0.008140 | 0.000343 | 0.007713 | 0.008946 | 0.008699 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -6.62%, p=0.0023 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.024s, clang 0.036s, gcc 0.041s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 351, clang 608, gcc 608. |

| section |
|---|---|
| startup |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001617 | 0.001610 | 0.000097 | 0.001417 | 0.001862 | 0.001699 | 0 |
| clang | 0.001600 | 0.001598 | 0.000060 | 0.001477 | 0.001699 | 0.001688 | 0 |
| gcc | 0.001551 | 0.001557 | 0.000088 | 0.001409 | 0.001760 | 0.001693 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -4.26%, p=0.0659 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.023s, clang 0.035s, gcc 0.039s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 255, clang 512, gcc 512. |

| section |
|---|---|
| brm1 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.026675 | 0.026871 | 0.001900 | 0.023657 | 0.030382 | 0.030326 | 0 |
| clang | 0.002994 | 0.003302 | 0.000808 | 0.002448 | 0.005201 | 0.005162 | 0 |
| gcc | 0.002719 | 0.003022 | 0.000715 | 0.002314 | 0.004584 | 0.004579 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -881.07%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.027s, clang 0.039s, gcc 0.043s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 391, clang 568, gcc 568. |

| section |
|---|---|
| brm2 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.014233 | 0.014268 | 0.000599 | 0.013448 | 0.015739 | 0.015592 | 0 |
| clang | 0.005208 | 0.005224 | 0.000195 | 0.004884 | 0.005492 | 0.005471 | 0 |
| gcc | 0.005335 | 0.005296 | 0.000175 | 0.004909 | 0.005541 | 0.005536 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -173.30%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.028s, clang 0.043s, gcc 0.046s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 435, clang 576, gcc 576. |

| section |
|---|---|
| brm3 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.012471 | 0.012580 | 0.000678 | 0.011753 | 0.014596 | 0.013792 | 1 |
| clang | 0.002299 | 0.002347 | 0.000348 | 0.001883 | 0.003328 | 0.003083 | 0 |
| gcc | 0.002122 | 0.002236 | 0.000400 | 0.001787 | 0.003079 | 0.002991 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -487.56%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.025s, clang 0.038s, gcc 0.041s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 455, clang 592, gcc 592. |

| section |
|---|---|
| divv |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.043098 | 0.043633 | 0.001216 | 0.042595 | 0.048308 | 0.044712 | 1 |
| clang | 0.043271 | 0.043630 | 0.000903 | 0.042618 | 0.046445 | 0.045026 | 0 |
| gcc | 0.043278 | 0.043660 | 0.001061 | 0.042608 | 0.046650 | 0.046525 | 2 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, margin +0.40%, p=0.9934 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.022s, clang 0.040s, gcc 0.047s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 323, clang 560, gcc 560. |

| section |
|---|---|
| divm |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.007044 | 0.007091 | 0.000225 | 0.006820 | 0.007723 | 0.007556 | 0 |
| clang | 0.006967 | 0.007057 | 0.000304 | 0.006823 | 0.008269 | 0.007384 | 1 |
| gcc | 0.007021 | 0.007162 | 0.000400 | 0.006778 | 0.008625 | 0.007776 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -1.11%, p=0.6867 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.026s, clang 0.042s, gcc 0.048s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 335, clang 664, gcc 664. |

| section |
|---|---|
| divd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.015726 | 0.015790 | 0.000272 | 0.015392 | 0.016525 | 0.016273 | 0 |
| clang | 0.006903 | 0.006909 | 0.000151 | 0.006638 | 0.007279 | 0.007109 | 0 |
| gcc | 0.006817 | 0.006827 | 0.000211 | 0.006328 | 0.007165 | 0.007108 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -130.69%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.026s, clang 0.040s, gcc 0.048s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 415, clang 1088, gcc 1088. |

| section |
|---|---|
| dgcd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.007589 | 0.007580 | 0.000204 | 0.007215 | 0.008036 | 0.007909 | 0 |
| clang | 0.004467 | 0.004521 | 0.000207 | 0.004226 | 0.005233 | 0.004741 | 0 |
| gcc | 0.004527 | 0.004457 | 0.000174 | 0.004066 | 0.004777 | 0.004611 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -69.90%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.031s, clang 0.037s, gcc 0.042s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 487, clang 632, gcc 632. |

| section |
|---|---|
| divpow2 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.046741 | 0.046592 | 0.000839 | 0.044721 | 0.048265 | 0.047674 | 0 |
| clang | 0.018054 | 0.017943 | 0.000533 | 0.016747 | 0.019101 | 0.018448 | 0 |
| gcc | 0.018036 | 0.017957 | 0.000313 | 0.016968 | 0.018482 | 0.018303 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -159.16%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.023s, clang 0.036s, gcc 0.041s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 315, clang 544, gcc 544. |

| section |
|---|---|
| ceildiv |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.013201 | 0.013162 | 0.000494 | 0.012528 | 0.014292 | 0.014167 | 0 |
| clang | 0.012779 | 0.012848 | 0.000501 | 0.011978 | 0.014135 | 0.013528 | 0 |
| gcc | 0.012742 | 0.012847 | 0.000526 | 0.012057 | 0.014300 | 0.014096 | 2 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -3.60%, p=0.0509 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.025s, clang 0.039s, gcc 0.043s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 351, clang 744, gcc 744. |

| section |
|---|---|
| mulc |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.054568 | 0.055165 | 0.001900 | 0.053334 | 0.060897 | 0.058126 | 0 |
| clang | 0.054618 | 0.055230 | 0.001692 | 0.053323 | 0.059809 | 0.058263 | 0 |
| gcc | 0.054705 | 0.054881 | 0.001251 | 0.053262 | 0.057935 | 0.056875 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, margin +0.09%, p=0.9096 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.025s, clang 0.037s, gcc 0.040s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 323, clang 552, gcc 552. |

| section |
|---|---|
| mulh |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.006764 | 0.006784 | 0.000128 | 0.006494 | 0.007013 | 0.006981 | 0 |
| clang | 0.001908 | 0.001900 | 0.000124 | 0.001735 | 0.002201 | 0.002149 | 0 |
| gcc | 0.001853 | 0.001857 | 0.000107 | 0.001685 | 0.002070 | 0.002004 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -265.11%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.035s, clang 0.039s, gcc 0.045s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 411, clang 512, gcc 512. |

| section |
|---|---|
| madd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.025901 | 0.026092 | 0.000699 | 0.025178 | 0.027826 | 0.027495 | 0 |
| clang | 0.026112 | 0.026214 | 0.000445 | 0.025565 | 0.027221 | 0.026960 | 0 |
| gcc | 0.026126 | 0.026272 | 0.000383 | 0.025732 | 0.027245 | 0.026933 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, margin +0.81%, p=0.5111 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.028s, clang 0.039s, gcc 0.043s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 323, clang 560, gcc 560. |

| section |
|---|---|
| sred1 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.053905 | 0.054159 | 0.000930 | 0.053232 | 0.057227 | 0.055771 | 1 |
| clang | 0.041065 | 0.041387 | 0.000851 | 0.040125 | 0.043499 | 0.042685 | 0 |
| gcc | 0.041284 | 0.041351 | 0.000858 | 0.040421 | 0.043591 | 0.042987 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -31.27%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.023s, clang 0.036s, gcc 0.045s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 295, clang 544, gcc 544. |

| section |
|---|---|
| powmod |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.009353 | 0.009408 | 0.000597 | 0.008532 | 0.010459 | 0.010355 | 0 |
| clang | 0.007705 | 0.007728 | 0.000151 | 0.007466 | 0.007977 | 0.007952 | 0 |
| gcc | 0.007658 | 0.007661 | 0.000138 | 0.007451 | 0.008026 | 0.007832 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -22.13%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.029s, clang 0.040s, gcc 0.044s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 411, clang 912, gcc 912. |

| section |
|---|---|
| popc |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.015103 | 0.016615 | 0.002794 | 0.014077 | 0.023539 | 0.022784 | 0 |
| clang | 0.005757 | 0.006055 | 0.000978 | 0.005117 | 0.009340 | 0.007404 | 0 |
| gcc | 0.005502 | 0.005943 | 0.000873 | 0.004940 | 0.008003 | 0.007413 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -174.48%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.034s, clang 0.046s, gcc 0.044s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 611, clang 1136, gcc 1136. |

| section |
|---|---|
| bitr |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.029014 | 0.029894 | 0.002920 | 0.026764 | 0.036670 | 0.034597 | 0 |
| clang | 0.003855 | 0.003796 | 0.000767 | 0.002628 | 0.005262 | 0.004906 | 0 |
| gcc | 0.003587 | 0.003700 | 0.000839 | 0.002573 | 0.005161 | 0.004954 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -708.83%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.036s, clang 0.045s, gcc 0.050s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 399, clang 1296, gcc 1296. |

| section |
|---|---|
| xsft |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.063802 | 0.065600 | 0.003730 | 0.063036 | 0.078523 | 0.070256 | 1 |
| clang | 0.034119 | 0.035669 | 0.002960 | 0.033666 | 0.044987 | 0.040783 | 1 |
| gcc | 0.034186 | 0.035726 | 0.003092 | 0.033735 | 0.047595 | 0.038645 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -86.99%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.030s, clang 0.037s, gcc 0.046s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 431, clang 608, gcc 608. |

| section |
|---|---|
| absd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.014180 | 0.014193 | 0.000268 | 0.013849 | 0.015106 | 0.014412 | 0 |
| clang | 0.012670 | 0.012697 | 0.000205 | 0.012349 | 0.013289 | 0.013032 | 1 |
| gcc | 0.012631 | 0.012704 | 0.000246 | 0.012238 | 0.013133 | 0.013132 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -12.27%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.030s, clang 0.037s, gcc 0.040s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 443, clang 600, gcc 600. |

| section |
|---|---|
| cltz |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.073659 | 0.073681 | 0.000881 | 0.072095 | 0.075066 | 0.075064 | 0 |
| clang | 0.029561 | 0.029611 | 0.000525 | 0.029038 | 0.031546 | 0.030345 | 1 |
| gcc | 0.029350 | 0.029516 | 0.000590 | 0.028718 | 0.031375 | 0.030494 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -150.97%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.039s, clang 0.035s, gcc 0.038s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 559, clang 608, gcc 608. |

| section |
|---|---|
| nest3d |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001570 | 0.001573 | 0.000047 | 0.001476 | 0.001688 | 0.001657 | 0 |
| clang | 0.001571 | 0.001577 | 0.000065 | 0.001509 | 0.001730 | 0.001717 | 0 |
| gcc | 0.001595 | 0.001601 | 0.000082 | 0.001473 | 0.001872 | 0.001695 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, margin +0.06%, p=0.8037 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.023s, clang 0.039s, gcc 0.043s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 335, clang 960, gcc 960. |

| section |
|---|---|
| unroll |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.013408 | 0.014028 | 0.001342 | 0.012942 | 0.016960 | 0.016865 | 0 |
| clang | 0.001727 | 0.001730 | 0.000137 | 0.001530 | 0.002118 | 0.001907 | 0 |
| gcc | 0.001582 | 0.001584 | 0.000075 | 0.001444 | 0.001767 | 0.001706 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -747.68%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.024s, clang 0.035s, gcc 0.039s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 343, clang 512, gcc 512. |

| section |
|---|---|
| mixop |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.031715 | 0.031919 | 0.001372 | 0.028887 | 0.035148 | 0.034310 | 0 |
| clang | 0.004810 | 0.004928 | 0.000404 | 0.004677 | 0.006669 | 0.005073 | 1 |
| gcc | 0.004702 | 0.004748 | 0.000231 | 0.004366 | 0.005615 | 0.004950 | 1 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -574.55%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.025s, clang 0.039s, gcc 0.041s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 463, clang 688, gcc 688. |

| section |
|---|---|
| loopinv |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.012272 | 0.012282 | 0.000297 | 0.011907 | 0.013387 | 0.012526 | 1 |
| clang | 0.002066 | 0.002103 | 0.000238 | 0.001792 | 0.003002 | 0.002388 | 1 |
| gcc | 0.001842 | 0.001812 | 0.000128 | 0.001614 | 0.002057 | 0.002019 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -566.38%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.025s, clang 0.035s, gcc 0.039s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 343, clang 512, gcc 512. |

| section |
|---|---|
| satadd |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.012200 | 0.012209 | 0.000189 | 0.011826 | 0.012570 | 0.012482 | 0 |
| clang | 0.004511 | 0.004542 | 0.000201 | 0.004245 | 0.004874 | 0.004865 | 0 |
| gcc | 0.004397 | 0.004430 | 0.000116 | 0.004253 | 0.004701 | 0.004595 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -177.47%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.029s, clang 0.039s, gcc 0.044s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 423, clang 760, gcc 760. |

| section |
|---|---|
| regp |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001439 | 0.001455 | 0.000067 | 0.001381 | 0.001598 | 0.001569 | 0 |
| clang | 0.001449 | 0.001464 | 0.000074 | 0.001341 | 0.001631 | 0.001564 | 0 |
| gcc | 0.001435 | 0.001453 | 0.000065 | 0.001375 | 0.001596 | 0.001544 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (gcc): loss, margin -0.32%, p=0.9200 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.024s, clang 0.034s, gcc 0.038s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 411, clang 512, gcc 512. |

| section |
|---|---|
| ilp |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.018783 | 0.018713 | 0.000318 | 0.018032 | 0.019113 | 0.019084 | 0 |
| clang | 0.022364 | 0.022293 | 0.000335 | 0.021640 | 0.022818 | 0.022772 | 0 |
| gcc | 0.022439 | 0.022380 | 0.000386 | 0.021681 | 0.023262 | 0.022929 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): win, margin +16.01%, p=0.0000 (significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.030s, clang 0.035s, gcc 0.041s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 371, clang 752, gcc 752. |

| section |
|---|---|
| stride3 |

| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |
|---|---|---|---|---|---|---|---|
| idol | 0.001686 | 0.001691 | 0.000105 | 0.001460 | 0.001932 | 0.001841 | 0 |
| clang | 0.001651 | 0.001655 | 0.000081 | 0.001482 | 0.001837 | 0.001740 | 0 |
| gcc | 0.001674 | 0.001705 | 0.000131 | 0.001501 | 0.001996 | 0.001967 | 0 |

| # | directive |
|---|---|
| 1 | Idol vs best rival (clang): loss, margin -2.07%, p=0.2172 (not significant). |

| # | directive |
|---|---|
| 1 | Compile time, source to executable (median of 5): idol 0.022s, clang 0.036s, gcc 0.040s. |

| # | directive |
|---|---|
| 1 | Object size (bytes): idol 287, clang 512, gcc 512. |

| section |
|---|---|
| history |

| # | directive |
|---|---|
| 1 | Per-case verdict history across runs. Any commit that regresses a case is visible here. |
| 2 | margin% = (rival_median - idol_median) / rival_median; negative = idol slower. |
| 3 | Source: bench/results/history.jsonl, one entry appended per run. |

| case | runs | first seen | last verdict | last margin% | worst margin% | best margin% |
|---|---|---|---|---|---|---|
| absd | 1 | 2026-09-12T21:48:24 | loss | -12.27% | -12.27% | -12.27% |
| arith | 2 | 2026-09-12T00:11:52 | loss | -1.07% | -1.07% | -0.85% |
| bigconst | 2 | 2026-09-12T00:11:52 | win | +0.23% | -0.35% | +0.23% |
| bitr | 1 | 2026-09-12T21:48:24 | loss | -708.83% | -708.83% | -708.83% |
| brm1 | 1 | 2026-09-12T21:48:24 | loss | -881.07% | -881.07% | -881.07% |
| brm2 | 1 | 2026-09-12T21:48:24 | loss | -173.30% | -173.30% | -173.30% |
| brm3 | 1 | 2026-09-12T21:48:24 | loss | -487.56% | -487.56% | -487.56% |
| ceildiv | 1 | 2026-09-12T21:48:24 | loss | -3.60% | -3.60% | -3.60% |
| cltz | 1 | 2026-09-12T21:48:24 | loss | -150.97% | -150.97% | -150.97% |
| dgcd | 1 | 2026-09-12T21:48:24 | loss | -69.90% | -69.90% | -69.90% |
| div | 4 | 2026-09-12T00:11:52 | loss | -0.13% | -35.72% | +0.15% |
| divd | 1 | 2026-09-12T21:48:24 | loss | -130.69% | -130.69% | -130.69% |
| divm | 1 | 2026-09-12T21:48:24 | loss | -1.11% | -1.11% | -1.11% |
| divpow2 | 1 | 2026-09-12T21:48:24 | loss | -159.16% | -159.16% | -159.16% |
| divv | 1 | 2026-09-12T21:48:24 | win | +0.40% | +0.40% | +0.40% |
| fib | 2 | 2026-09-12T00:11:52 | loss | -0.54% | -0.54% | +2.31% |
| ilp | 1 | 2026-09-12T21:48:24 | win | +16.01% | +16.01% | +16.01% |
| loopinv | 1 | 2026-09-12T21:48:24 | loss | -566.38% | -566.38% | -566.38% |
| madd | 1 | 2026-09-12T21:48:24 | win | +0.81% | +0.81% | +0.81% |
| mixop | 1 | 2026-09-12T21:48:24 | loss | -574.55% | -574.55% | -574.55% |
| mul13 | 4 | 2026-09-12T00:11:52 | win | +0.32% | -7.52% | +1.26% |
| mulc | 1 | 2026-09-12T21:48:24 | win | +0.09% | +0.09% | +0.09% |
| mulh | 1 | 2026-09-12T21:48:24 | loss | -265.11% | -265.11% | -265.11% |
| nest | 4 | 2026-09-12T00:11:52 | loss | -1.38% | -44.04% | -1.38% |
| nest3d | 1 | 2026-09-12T21:48:24 | win | +0.06% | +0.06% | +0.06% |
| popc | 1 | 2026-09-12T21:48:24 | loss | -174.48% | -174.48% | -174.48% |
| powmod | 1 | 2026-09-12T21:48:24 | loss | -22.13% | -22.13% | -22.13% |
| regp | 1 | 2026-09-12T21:48:24 | loss | -0.32% | -0.32% | -0.32% |
| satadd | 1 | 2026-09-12T21:48:24 | loss | -177.47% | -177.47% | -177.47% |
| sred1 | 1 | 2026-09-12T21:48:24 | loss | -31.27% | -31.27% | -31.27% |
| startup | 2 | 2026-09-12T00:11:52 | loss | -4.26% | -4.38% | -4.26% |
| stride3 | 1 | 2026-09-12T21:48:24 | loss | -2.07% | -2.07% | -2.07% |
| sum | 2 | 2026-09-12T00:11:52 | loss | -2.45% | -2.95% | -2.45% |
| unroll | 1 | 2026-09-12T21:48:24 | loss | -747.68% | -747.68% | -747.68% |
| upbranch | 4 | 2026-09-12T00:11:52 | loss | -6.62% | -24.09% | -6.62% |
| xsft | 1 | 2026-09-12T21:48:24 | loss | -86.99% | -86.99% | -86.99% |
| zerotrip | 4 | 2026-09-12T00:11:52 | win | +0.15% | -120.32% | +0.15% |
