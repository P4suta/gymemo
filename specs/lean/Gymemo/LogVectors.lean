import Gymemo.Log

/-!
# Results of the Swift code for the rules of the log

`Tests/GymemoCoreTests/LeanVectors.swift` writes this file from what `TrainingLog.apply` and `TrainingLog.make` return, and `mise x -- just gen` runs it.
A package test fails while this file differs from those results, so no change by hand lasts.
After `mise x -- just gen`, `lake build --wfail` in `specs/lean` checks the theorems.
Each theorem holds when the model of `Gymemo/Log.lean` gives the result of the Swift code, and Lean's kernel computes the model's result after the rewrites that the notes below name.
When the theorem of a sequence fails, `#eval ((outcomes Log.empty seed1Commands).1.zip seed1Steps).findIdx? (fun (model, swift) => model != swift)` gives the place of the first step that differs, counted from zero.

An exercise or a set bears the number in the last four bytes of its UUID.
A day is its `LocalDay.dayNumber`, a weight counts hundredths of a kilogram, and the memos of a log lie in the order of their days.
A run of sets whose identifiers count up by one and whose other fields agree is `(List.range n).map`, and a run of one repeated row is `List.replicate`.
A name or a memo text is a number of the tables below, in the order of first use.
A command holds `.refused` for a text that `ExerciseName.parse` or `Memo.parse` refuses, and `.nothing` for a memo text that holds nothing to keep.

Each sequence other than the set limit also holds the rows of a store that receives the changes of each accepted command, the log of `applied`, and `Valid` for its last log.

The sequence of the exercise limit fills a log to a thousand exercises and refuses one more as `.full`.
It replaces the full log before its end, because `make` over a thousand distinct exercises ran out of the memory of the proof run.

The sequence of the set limit fills a log to a million sets and refuses one more as `.full`, while the full log still refuses a set of no exercise and a repeated identifier for those reasons.
Lean's kernel can't compare or search a million sets, so that sequence holds a theorem for each command and `Valid` for each of its logs in place of the theorems of a whole sequence.
Those theorems rewrite the search and the count of the sets before they decide.

Rows that `TrainingLog.make` refuses break the invariant of `Valid` that the refusal names, and rows that form a log keep `Valid`.
The theorems over a million rows rewrite the length of `List.replicate` before they decide, because Lean's kernel can't count so many rows.
-/

-- The names by their numbers.
--   0 "懸垂"
--   1 "デッドリフト"
--   2 "引用\"と\\"
--   3 "ガ"
--   4 "ベンチプレス"
--   5 "スクワット"
--   6 "プランク"
--   7 "ああああああああああああああああああああああああああああああああああああああああ"
--   8 "種目1"
--   9 "種目2"
--   10 "種目3"
--   11 "種目4"
--   12 "種目5"
--   13 "種目6"
--   14 "種目7"
--   15 "種目8"
--   16 "種目9"
--   17 "種目10"
--   18 "種目11"
--   19 "種目12"
--   20 "種目13"
--   21 "種目14"
--   22 "種目15"
--   23 "種目16"
--   24 "種目17"
--   25 "種目18"
--   26 "種目19"
--   27 "種目20"
--   28 "種目21"
--   29 "種目22"
--   30 "種目23"
--   31 "種目24"
--   32 "種目25"
--   33 "種目26"
--   34 "種目27"
--   35 "種目28"
--   36 "種目29"
--   37 "種目30"
--   38 "種目31"
--   39 "種目32"
--   40 "種目33"
--   41 "種目34"
--   42 "種目35"
--   43 "種目36"
--   44 "種目37"
--   45 "種目38"
--   46 "種目39"
--   47 "種目40"
--   48 "種目41"
--   49 "種目42"
--   50 "種目43"
--   51 "種目44"
--   52 "種目45"
--   53 "種目46"
--   54 "種目47"
--   55 "種目48"
--   56 "種目49"
--   57 "種目50"
--   58 "種目51"
--   59 "種目52"
--   60 "種目53"
--   61 "種目54"
--   62 "種目55"
--   63 "種目56"
--   64 "種目57"
--   65 "種目58"
--   66 "種目59"
--   67 "種目60"
--   68 "種目61"
--   69 "種目62"
--   70 "種目63"
--   71 "種目64"
--   72 "種目65"
--   73 "種目66"
--   74 "種目67"
--   75 "種目68"
--   76 "種目69"
--   77 "種目70"
--   78 "種目71"
--   79 "種目72"
--   80 "種目73"
--   81 "種目74"
--   82 "種目75"
--   83 "種目76"
--   84 "種目77"
--   85 "種目78"
--   86 "種目79"
--   87 "種目80"
--   88 "種目81"
--   89 "種目82"
--   90 "種目83"
--   91 "種目84"
--   92 "種目85"
--   93 "種目86"
--   94 "種目87"
--   95 "種目88"
--   96 "種目89"
--   97 "種目90"
--   98 "種目91"
--   99 "種目92"
--   100 "種目93"
--   101 "種目94"
--   102 "種目95"
--   103 "種目96"
--   104 "種目97"
--   105 "種目98"
--   106 "種目99"
--   107 "種目100"
--   108 "種目101"
--   109 "種目102"
--   110 "種目103"
--   111 "種目104"
--   112 "種目105"
--   113 "種目106"
--   114 "種目107"
--   115 "種目108"
--   116 "種目109"
--   117 "種目110"
--   118 "種目111"
--   119 "種目112"
--   120 "種目113"
--   121 "種目114"
--   122 "種目115"
--   123 "種目116"
--   124 "種目117"
--   125 "種目118"
--   126 "種目119"
--   127 "種目120"
--   128 "種目121"
--   129 "種目122"
--   130 "種目123"
--   131 "種目124"
--   132 "種目125"
--   133 "種目126"
--   134 "種目127"
--   135 "種目128"
--   136 "種目129"
--   137 "種目130"
--   138 "種目131"
--   139 "種目132"
--   140 "種目133"
--   141 "種目134"
--   142 "種目135"
--   143 "種目136"
--   144 "種目137"
--   145 "種目138"
--   146 "種目139"
--   147 "種目140"
--   148 "種目141"
--   149 "種目142"
--   150 "種目143"
--   151 "種目144"
--   152 "種目145"
--   153 "種目146"
--   154 "種目147"
--   155 "種目148"
--   156 "種目149"
--   157 "種目150"
--   158 "種目151"
--   159 "種目152"
--   160 "種目153"
--   161 "種目154"
--   162 "種目155"
--   163 "種目156"
--   164 "種目157"
--   165 "種目158"
--   166 "種目159"
--   167 "種目160"
--   168 "種目161"
--   169 "種目162"
--   170 "種目163"
--   171 "種目164"
--   172 "種目165"
--   173 "種目166"
--   174 "種目167"
--   175 "種目168"
--   176 "種目169"
--   177 "種目170"
--   178 "種目171"
--   179 "種目172"
--   180 "種目173"
--   181 "種目174"
--   182 "種目175"
--   183 "種目176"
--   184 "種目177"
--   185 "種目178"
--   186 "種目179"
--   187 "種目180"
--   188 "種目181"
--   189 "種目182"
--   190 "種目183"
--   191 "種目184"
--   192 "種目185"
--   193 "種目186"
--   194 "種目187"
--   195 "種目188"
--   196 "種目189"
--   197 "種目190"
--   198 "種目191"
--   199 "種目192"
--   200 "種目193"
--   201 "種目194"
--   202 "種目195"
--   203 "種目196"
--   204 "種目197"
--   205 "種目198"
--   206 "種目199"
--   207 "種目200"
--   208 "種目201"
--   209 "種目202"
--   210 "種目203"
--   211 "種目204"
--   212 "種目205"
--   213 "種目206"
--   214 "種目207"
--   215 "種目208"
--   216 "種目209"
--   217 "種目210"
--   218 "種目211"
--   219 "種目212"
--   220 "種目213"
--   221 "種目214"
--   222 "種目215"
--   223 "種目216"
--   224 "種目217"
--   225 "種目218"
--   226 "種目219"
--   227 "種目220"
--   228 "種目221"
--   229 "種目222"
--   230 "種目223"
--   231 "種目224"
--   232 "種目225"
--   233 "種目226"
--   234 "種目227"
--   235 "種目228"
--   236 "種目229"
--   237 "種目230"
--   238 "種目231"
--   239 "種目232"
--   240 "種目233"
--   241 "種目234"
--   242 "種目235"
--   243 "種目236"
--   244 "種目237"
--   245 "種目238"
--   246 "種目239"
--   247 "種目240"
--   248 "種目241"
--   249 "種目242"
--   250 "種目243"
--   251 "種目244"
--   252 "種目245"
--   253 "種目246"
--   254 "種目247"
--   255 "種目248"
--   256 "種目249"
--   257 "種目250"
--   258 "種目251"
--   259 "種目252"
--   260 "種目253"
--   261 "種目254"
--   262 "種目255"
--   263 "種目256"
--   264 "種目257"
--   265 "種目258"
--   266 "種目259"
--   267 "種目260"
--   268 "種目261"
--   269 "種目262"
--   270 "種目263"
--   271 "種目264"
--   272 "種目265"
--   273 "種目266"
--   274 "種目267"
--   275 "種目268"
--   276 "種目269"
--   277 "種目270"
--   278 "種目271"
--   279 "種目272"
--   280 "種目273"
--   281 "種目274"
--   282 "種目275"
--   283 "種目276"
--   284 "種目277"
--   285 "種目278"
--   286 "種目279"
--   287 "種目280"
--   288 "種目281"
--   289 "種目282"
--   290 "種目283"
--   291 "種目284"
--   292 "種目285"
--   293 "種目286"
--   294 "種目287"
--   295 "種目288"
--   296 "種目289"
--   297 "種目290"
--   298 "種目291"
--   299 "種目292"
--   300 "種目293"
--   301 "種目294"
--   302 "種目295"
--   303 "種目296"
--   304 "種目297"
--   305 "種目298"
--   306 "種目299"
--   307 "種目300"
--   308 "種目301"
--   309 "種目302"
--   310 "種目303"
--   311 "種目304"
--   312 "種目305"
--   313 "種目306"
--   314 "種目307"
--   315 "種目308"
--   316 "種目309"
--   317 "種目310"
--   318 "種目311"
--   319 "種目312"
--   320 "種目313"
--   321 "種目314"
--   322 "種目315"
--   323 "種目316"
--   324 "種目317"
--   325 "種目318"
--   326 "種目319"
--   327 "種目320"
--   328 "種目321"
--   329 "種目322"
--   330 "種目323"
--   331 "種目324"
--   332 "種目325"
--   333 "種目326"
--   334 "種目327"
--   335 "種目328"
--   336 "種目329"
--   337 "種目330"
--   338 "種目331"
--   339 "種目332"
--   340 "種目333"
--   341 "種目334"
--   342 "種目335"
--   343 "種目336"
--   344 "種目337"
--   345 "種目338"
--   346 "種目339"
--   347 "種目340"
--   348 "種目341"
--   349 "種目342"
--   350 "種目343"
--   351 "種目344"
--   352 "種目345"
--   353 "種目346"
--   354 "種目347"
--   355 "種目348"
--   356 "種目349"
--   357 "種目350"
--   358 "種目351"
--   359 "種目352"
--   360 "種目353"
--   361 "種目354"
--   362 "種目355"
--   363 "種目356"
--   364 "種目357"
--   365 "種目358"
--   366 "種目359"
--   367 "種目360"
--   368 "種目361"
--   369 "種目362"
--   370 "種目363"
--   371 "種目364"
--   372 "種目365"
--   373 "種目366"
--   374 "種目367"
--   375 "種目368"
--   376 "種目369"
--   377 "種目370"
--   378 "種目371"
--   379 "種目372"
--   380 "種目373"
--   381 "種目374"
--   382 "種目375"
--   383 "種目376"
--   384 "種目377"
--   385 "種目378"
--   386 "種目379"
--   387 "種目380"
--   388 "種目381"
--   389 "種目382"
--   390 "種目383"
--   391 "種目384"
--   392 "種目385"
--   393 "種目386"
--   394 "種目387"
--   395 "種目388"
--   396 "種目389"
--   397 "種目390"
--   398 "種目391"
--   399 "種目392"
--   400 "種目393"
--   401 "種目394"
--   402 "種目395"
--   403 "種目396"
--   404 "種目397"
--   405 "種目398"
--   406 "種目399"
--   407 "種目400"
--   408 "種目401"
--   409 "種目402"
--   410 "種目403"
--   411 "種目404"
--   412 "種目405"
--   413 "種目406"
--   414 "種目407"
--   415 "種目408"
--   416 "種目409"
--   417 "種目410"
--   418 "種目411"
--   419 "種目412"
--   420 "種目413"
--   421 "種目414"
--   422 "種目415"
--   423 "種目416"
--   424 "種目417"
--   425 "種目418"
--   426 "種目419"
--   427 "種目420"
--   428 "種目421"
--   429 "種目422"
--   430 "種目423"
--   431 "種目424"
--   432 "種目425"
--   433 "種目426"
--   434 "種目427"
--   435 "種目428"
--   436 "種目429"
--   437 "種目430"
--   438 "種目431"
--   439 "種目432"
--   440 "種目433"
--   441 "種目434"
--   442 "種目435"
--   443 "種目436"
--   444 "種目437"
--   445 "種目438"
--   446 "種目439"
--   447 "種目440"
--   448 "種目441"
--   449 "種目442"
--   450 "種目443"
--   451 "種目444"
--   452 "種目445"
--   453 "種目446"
--   454 "種目447"
--   455 "種目448"
--   456 "種目449"
--   457 "種目450"
--   458 "種目451"
--   459 "種目452"
--   460 "種目453"
--   461 "種目454"
--   462 "種目455"
--   463 "種目456"
--   464 "種目457"
--   465 "種目458"
--   466 "種目459"
--   467 "種目460"
--   468 "種目461"
--   469 "種目462"
--   470 "種目463"
--   471 "種目464"
--   472 "種目465"
--   473 "種目466"
--   474 "種目467"
--   475 "種目468"
--   476 "種目469"
--   477 "種目470"
--   478 "種目471"
--   479 "種目472"
--   480 "種目473"
--   481 "種目474"
--   482 "種目475"
--   483 "種目476"
--   484 "種目477"
--   485 "種目478"
--   486 "種目479"
--   487 "種目480"
--   488 "種目481"
--   489 "種目482"
--   490 "種目483"
--   491 "種目484"
--   492 "種目485"
--   493 "種目486"
--   494 "種目487"
--   495 "種目488"
--   496 "種目489"
--   497 "種目490"
--   498 "種目491"
--   499 "種目492"
--   500 "種目493"
--   501 "種目494"
--   502 "種目495"
--   503 "種目496"
--   504 "種目497"
--   505 "種目498"
--   506 "種目499"
--   507 "種目500"
--   508 "種目501"
--   509 "種目502"
--   510 "種目503"
--   511 "種目504"
--   512 "種目505"
--   513 "種目506"
--   514 "種目507"
--   515 "種目508"
--   516 "種目509"
--   517 "種目510"
--   518 "種目511"
--   519 "種目512"
--   520 "種目513"
--   521 "種目514"
--   522 "種目515"
--   523 "種目516"
--   524 "種目517"
--   525 "種目518"
--   526 "種目519"
--   527 "種目520"
--   528 "種目521"
--   529 "種目522"
--   530 "種目523"
--   531 "種目524"
--   532 "種目525"
--   533 "種目526"
--   534 "種目527"
--   535 "種目528"
--   536 "種目529"
--   537 "種目530"
--   538 "種目531"
--   539 "種目532"
--   540 "種目533"
--   541 "種目534"
--   542 "種目535"
--   543 "種目536"
--   544 "種目537"
--   545 "種目538"
--   546 "種目539"
--   547 "種目540"
--   548 "種目541"
--   549 "種目542"
--   550 "種目543"
--   551 "種目544"
--   552 "種目545"
--   553 "種目546"
--   554 "種目547"
--   555 "種目548"
--   556 "種目549"
--   557 "種目550"
--   558 "種目551"
--   559 "種目552"
--   560 "種目553"
--   561 "種目554"
--   562 "種目555"
--   563 "種目556"
--   564 "種目557"
--   565 "種目558"
--   566 "種目559"
--   567 "種目560"
--   568 "種目561"
--   569 "種目562"
--   570 "種目563"
--   571 "種目564"
--   572 "種目565"
--   573 "種目566"
--   574 "種目567"
--   575 "種目568"
--   576 "種目569"
--   577 "種目570"
--   578 "種目571"
--   579 "種目572"
--   580 "種目573"
--   581 "種目574"
--   582 "種目575"
--   583 "種目576"
--   584 "種目577"
--   585 "種目578"
--   586 "種目579"
--   587 "種目580"
--   588 "種目581"
--   589 "種目582"
--   590 "種目583"
--   591 "種目584"
--   592 "種目585"
--   593 "種目586"
--   594 "種目587"
--   595 "種目588"
--   596 "種目589"
--   597 "種目590"
--   598 "種目591"
--   599 "種目592"
--   600 "種目593"
--   601 "種目594"
--   602 "種目595"
--   603 "種目596"
--   604 "種目597"
--   605 "種目598"
--   606 "種目599"
--   607 "種目600"
--   608 "種目601"
--   609 "種目602"
--   610 "種目603"
--   611 "種目604"
--   612 "種目605"
--   613 "種目606"
--   614 "種目607"
--   615 "種目608"
--   616 "種目609"
--   617 "種目610"
--   618 "種目611"
--   619 "種目612"
--   620 "種目613"
--   621 "種目614"
--   622 "種目615"
--   623 "種目616"
--   624 "種目617"
--   625 "種目618"
--   626 "種目619"
--   627 "種目620"
--   628 "種目621"
--   629 "種目622"
--   630 "種目623"
--   631 "種目624"
--   632 "種目625"
--   633 "種目626"
--   634 "種目627"
--   635 "種目628"
--   636 "種目629"
--   637 "種目630"
--   638 "種目631"
--   639 "種目632"
--   640 "種目633"
--   641 "種目634"
--   642 "種目635"
--   643 "種目636"
--   644 "種目637"
--   645 "種目638"
--   646 "種目639"
--   647 "種目640"
--   648 "種目641"
--   649 "種目642"
--   650 "種目643"
--   651 "種目644"
--   652 "種目645"
--   653 "種目646"
--   654 "種目647"
--   655 "種目648"
--   656 "種目649"
--   657 "種目650"
--   658 "種目651"
--   659 "種目652"
--   660 "種目653"
--   661 "種目654"
--   662 "種目655"
--   663 "種目656"
--   664 "種目657"
--   665 "種目658"
--   666 "種目659"
--   667 "種目660"
--   668 "種目661"
--   669 "種目662"
--   670 "種目663"
--   671 "種目664"
--   672 "種目665"
--   673 "種目666"
--   674 "種目667"
--   675 "種目668"
--   676 "種目669"
--   677 "種目670"
--   678 "種目671"
--   679 "種目672"
--   680 "種目673"
--   681 "種目674"
--   682 "種目675"
--   683 "種目676"
--   684 "種目677"
--   685 "種目678"
--   686 "種目679"
--   687 "種目680"
--   688 "種目681"
--   689 "種目682"
--   690 "種目683"
--   691 "種目684"
--   692 "種目685"
--   693 "種目686"
--   694 "種目687"
--   695 "種目688"
--   696 "種目689"
--   697 "種目690"
--   698 "種目691"
--   699 "種目692"
--   700 "種目693"
--   701 "種目694"
--   702 "種目695"
--   703 "種目696"
--   704 "種目697"
--   705 "種目698"
--   706 "種目699"
--   707 "種目700"
--   708 "種目701"
--   709 "種目702"
--   710 "種目703"
--   711 "種目704"
--   712 "種目705"
--   713 "種目706"
--   714 "種目707"
--   715 "種目708"
--   716 "種目709"
--   717 "種目710"
--   718 "種目711"
--   719 "種目712"
--   720 "種目713"
--   721 "種目714"
--   722 "種目715"
--   723 "種目716"
--   724 "種目717"
--   725 "種目718"
--   726 "種目719"
--   727 "種目720"
--   728 "種目721"
--   729 "種目722"
--   730 "種目723"
--   731 "種目724"
--   732 "種目725"
--   733 "種目726"
--   734 "種目727"
--   735 "種目728"
--   736 "種目729"
--   737 "種目730"
--   738 "種目731"
--   739 "種目732"
--   740 "種目733"
--   741 "種目734"
--   742 "種目735"
--   743 "種目736"
--   744 "種目737"
--   745 "種目738"
--   746 "種目739"
--   747 "種目740"
--   748 "種目741"
--   749 "種目742"
--   750 "種目743"
--   751 "種目744"
--   752 "種目745"
--   753 "種目746"
--   754 "種目747"
--   755 "種目748"
--   756 "種目749"
--   757 "種目750"
--   758 "種目751"
--   759 "種目752"
--   760 "種目753"
--   761 "種目754"
--   762 "種目755"
--   763 "種目756"
--   764 "種目757"
--   765 "種目758"
--   766 "種目759"
--   767 "種目760"
--   768 "種目761"
--   769 "種目762"
--   770 "種目763"
--   771 "種目764"
--   772 "種目765"
--   773 "種目766"
--   774 "種目767"
--   775 "種目768"
--   776 "種目769"
--   777 "種目770"
--   778 "種目771"
--   779 "種目772"
--   780 "種目773"
--   781 "種目774"
--   782 "種目775"
--   783 "種目776"
--   784 "種目777"
--   785 "種目778"
--   786 "種目779"
--   787 "種目780"
--   788 "種目781"
--   789 "種目782"
--   790 "種目783"
--   791 "種目784"
--   792 "種目785"
--   793 "種目786"
--   794 "種目787"
--   795 "種目788"
--   796 "種目789"
--   797 "種目790"
--   798 "種目791"
--   799 "種目792"
--   800 "種目793"
--   801 "種目794"
--   802 "種目795"
--   803 "種目796"
--   804 "種目797"
--   805 "種目798"
--   806 "種目799"
--   807 "種目800"
--   808 "種目801"
--   809 "種目802"
--   810 "種目803"
--   811 "種目804"
--   812 "種目805"
--   813 "種目806"
--   814 "種目807"
--   815 "種目808"
--   816 "種目809"
--   817 "種目810"
--   818 "種目811"
--   819 "種目812"
--   820 "種目813"
--   821 "種目814"
--   822 "種目815"
--   823 "種目816"
--   824 "種目817"
--   825 "種目818"
--   826 "種目819"
--   827 "種目820"
--   828 "種目821"
--   829 "種目822"
--   830 "種目823"
--   831 "種目824"
--   832 "種目825"
--   833 "種目826"
--   834 "種目827"
--   835 "種目828"
--   836 "種目829"
--   837 "種目830"
--   838 "種目831"
--   839 "種目832"
--   840 "種目833"
--   841 "種目834"
--   842 "種目835"
--   843 "種目836"
--   844 "種目837"
--   845 "種目838"
--   846 "種目839"
--   847 "種目840"
--   848 "種目841"
--   849 "種目842"
--   850 "種目843"
--   851 "種目844"
--   852 "種目845"
--   853 "種目846"
--   854 "種目847"
--   855 "種目848"
--   856 "種目849"
--   857 "種目850"
--   858 "種目851"
--   859 "種目852"
--   860 "種目853"
--   861 "種目854"
--   862 "種目855"
--   863 "種目856"
--   864 "種目857"
--   865 "種目858"
--   866 "種目859"
--   867 "種目860"
--   868 "種目861"
--   869 "種目862"
--   870 "種目863"
--   871 "種目864"
--   872 "種目865"
--   873 "種目866"
--   874 "種目867"
--   875 "種目868"
--   876 "種目869"
--   877 "種目870"
--   878 "種目871"
--   879 "種目872"
--   880 "種目873"
--   881 "種目874"
--   882 "種目875"
--   883 "種目876"
--   884 "種目877"
--   885 "種目878"
--   886 "種目879"
--   887 "種目880"
--   888 "種目881"
--   889 "種目882"
--   890 "種目883"
--   891 "種目884"
--   892 "種目885"
--   893 "種目886"
--   894 "種目887"
--   895 "種目888"
--   896 "種目889"
--   897 "種目890"
--   898 "種目891"
--   899 "種目892"
--   900 "種目893"
--   901 "種目894"
--   902 "種目895"
--   903 "種目896"
--   904 "種目897"
--   905 "種目898"
--   906 "種目899"
--   907 "種目900"
--   908 "種目901"
--   909 "種目902"
--   910 "種目903"
--   911 "種目904"
--   912 "種目905"
--   913 "種目906"
--   914 "種目907"
--   915 "種目908"
--   916 "種目909"
--   917 "種目910"
--   918 "種目911"
--   919 "種目912"
--   920 "種目913"
--   921 "種目914"
--   922 "種目915"
--   923 "種目916"
--   924 "種目917"
--   925 "種目918"
--   926 "種目919"
--   927 "種目920"
--   928 "種目921"
--   929 "種目922"
--   930 "種目923"
--   931 "種目924"
--   932 "種目925"
--   933 "種目926"
--   934 "種目927"
--   935 "種目928"
--   936 "種目929"
--   937 "種目930"
--   938 "種目931"
--   939 "種目932"
--   940 "種目933"
--   941 "種目934"
--   942 "種目935"
--   943 "種目936"
--   944 "種目937"
--   945 "種目938"
--   946 "種目939"
--   947 "種目940"
--   948 "種目941"
--   949 "種目942"
--   950 "種目943"
--   951 "種目944"
--   952 "種目945"
--   953 "種目946"
--   954 "種目947"
--   955 "種目948"
--   956 "種目949"
--   957 "種目950"
--   958 "種目951"
--   959 "種目952"
--   960 "種目953"
--   961 "種目954"
--   962 "種目955"
--   963 "種目956"
--   964 "種目957"
--   965 "種目958"
--   966 "種目959"
--   967 "種目960"
--   968 "種目961"
--   969 "種目962"
--   970 "種目963"
--   971 "種目964"
--   972 "種目965"
--   973 "種目966"
--   974 "種目967"
--   975 "種目968"
--   976 "種目969"
--   977 "種目970"
--   978 "種目971"
--   979 "種目972"
--   980 "種目973"
--   981 "種目974"
--   982 "種目975"
--   983 "種目976"
--   984 "種目977"
--   985 "種目978"
--   986 "種目979"
--   987 "種目980"
--   988 "種目981"
--   989 "種目982"
--   990 "種目983"
--   991 "種目984"
--   992 "種目985"
--   993 "種目986"
--   994 "種目987"
--   995 "種目988"
--   996 "種目989"
--   997 "種目990"
--   998 "種目991"
--   999 "種目992"
--   1000 "種目993"
--   1001 "種目994"
--   1002 "種目995"
--   1003 "種目996"
--   1004 "種目997"
--   1005 "種目998"
--   1006 "種目999"
--   1007 "種目1000"
--   1008 "種目1001"

-- The memo texts by their numbers.
--   0 "デッドリフト"
--   1 "ベンチプレス"
--   2 "スクワット"
--   3 "カ\u{3099}"
--   4 "懸垂"
--   5 "ベンチ\nプレス"
--   6 "引用\"と\\"
--   7 "古い記録"
--   8 "肩が重い"
--   9 "新しい記録"
--   10 "一行目\n二行目"
--   11 "腰は軽い"

namespace Gymemo.Log.Vectors

/-- The limits of `TrainingLog`. -/
theorem limits :
    maximumExercises = 1000 ∧
    maximumSets = 1000000 := by
  decide +kernel

/-! ## Seed 1 of `RandomCommand.next`: 150 commands, of which the log accepted 51 and refused 99 -/

def seed1Commands : List Command := [
  .logSet 16 4 20435 7500 11,
  .editExercise 2 (.accepted 0) .arms,
  .editExercise 5 (.refused .controlCharacter) .other,
  .logSet 31 5 20433 7500 8,
  .logSet 12 3 20436 5000 10,
  .editExercise 3 (.accepted 1) .arms,
  .addExercise 1 (.accepted 1) .chest,
  .logSet 32 4 20436 0 10,
  .deleteSet 9,
  .editExercise 4 (.refused .empty) .shoulders,
  .editExercise 2 (.accepted 0) .other,
  .addExercise 5 (.accepted 2) .legs,
  .logSet 28 5 20437 5000 8,
  .editExercise 5 (.refused .empty) .chest,
  .logSet 15 1 20438 2500 6,
  .deleteExercise 2,
  .addExercise 1 (.accepted 1) .shoulders,
  .logSet 4 3 20436 5000 8,
  .logSet 30 6 20437 2500 3,
  .writeMemo 20438 (.kept 0),
  .logSet 11 5 20434 2500 11,
  .addExercise 1 (.accepted 0) .legs,
  .logSet 13 5 20434 2500 2,
  .editSet 14 0 4,
  .logSet 36 5 20433 2500 5,
  .addExercise 2 (.accepted 0) .arms,
  .deleteSet 27,
  .logSet 24 4 20435 0 8,
  .addExercise 6 (.accepted 0) .shoulders,
  .logSet 36 4 20434 2500 6,
  .editSet 35 0 7,
  .editExercise 1 (.accepted 3) .other,
  .logSet 5 4 20437 0 6,
  .setExerciseArchived 3 false,
  .logSet 34 4 20436 5000 9,
  .editExercise 5 (.accepted 4) .legs,
  .writeMemo 20436 (.kept 0),
  .logSet 19 3 20435 5000 11,
  .addExercise 4 (.accepted 4) .abdominals,
  .setExerciseArchived 3 true,
  .editSet 40 0 9,
  .writeMemo 20435 (.kept 1),
  .setExerciseArchived 5 false,
  .logSet 37 1 20438 5000 4,
  .setExerciseArchived 2 false,
  .addExercise 5 (.accepted 3) .back,
  .deleteSet 22,
  .logSet 19 1 20435 2500 5,
  .deleteSet 18,
  .editSet 1 2500 2,
  .deleteSet 6,
  .setExerciseArchived 6 true,
  .deleteExercise 1,
  .logSet 6 5 20438 7500 12,
  .logSet 33 6 20435 7500 11,
  .deleteExercise 2,
  .writeMemo 20436 (.kept 1),
  .logSet 18 4 20434 2500 3,
  .logSet 3 4 20433 7500 5,
  .editExercise 5 (.accepted 4) .shoulders,
  .deleteSet 25,
  .logSet 36 4 20434 5000 12,
  .deleteExercise 5,
  .editSet 10 7500 4,
  .addExercise 4 (.accepted 1) .shoulders,
  .logSet 26 5 20433 2500 3,
  .setExerciseArchived 5 true,
  .editExercise 6 (.accepted 5) .legs,
  .logSet 6 6 20435 5000 3,
  .addExercise 1 (.refused .empty) .shoulders,
  .deleteSet 26,
  .logSet 30 5 20436 0 3,
  .setExerciseArchived 2 true,
  .writeMemo 20436 (.kept 2),
  .editExercise 1 (.refused .controlCharacter) .shoulders,
  .addExercise 1 (.accepted 5) .arms,
  .logSet 19 3 20433 7500 6,
  .logSet 27 4 20434 5000 9,
  .logSet 23 2 20436 2500 6,
  .deleteExercise 2,
  .writeMemo 20433 (.kept 1),
  .editSet 23 7500 12,
  .editSet 10 7500 3,
  .deleteExercise 2,
  .deleteExercise 1,
  .setExerciseArchived 6 true,
  .setExerciseArchived 5 true,
  .setExerciseArchived 6 true,
  .addExercise 2 (.refused .empty) .other,
  .logSet 27 2 20436 5000 10,
  .logSet 33 4 20436 5000 3,
  .editSet 20 0 5,
  .editSet 16 5000 10,
  .logSet 38 4 20434 5000 7,
  .logSet 6 4 20433 0 10,
  .editExercise 5 (.accepted 0) .chest,
  .editSet 16 0 12,
  .setExerciseArchived 5 false,
  .editSet 18 7500 9,
  .logSet 21 6 20433 2500 8,
  .deleteSet 34,
  .deleteExercise 4,
  .writeMemo 20437 (.kept 3),
  .addExercise 4 (.accepted 0) .legs,
  .logSet 19 2 20435 5000 12,
  .deleteSet 19,
  .editExercise 5 (.accepted 4) .shoulders,
  .editExercise 1 (.refused .controlCharacter) .chest,
  .editExercise 5 (.accepted 4) .back,
  .editSet 35 0 4,
  .logSet 29 6 20436 0 3,
  .editSet 23 5000 7,
  .setExerciseArchived 6 false,
  .logSet 1 5 20437 2500 11,
  .addExercise 4 (.accepted 4) .arms,
  .deleteExercise 2,
  .setExerciseArchived 4 true,
  .editExercise 6 (.accepted 5) .arms,
  .deleteSet 40,
  .editSet 19 2500 8,
  .logSet 33 6 20438 0 6,
  .logSet 32 2 20434 0 5,
  .deleteSet 38,
  .setExerciseArchived 4 true,
  .addExercise 3 (.refused .empty) .back,
  .logSet 21 4 20437 5000 1,
  .editExercise 1 (.refused .empty) .chest,
  .writeMemo 20437 .nothing,
  .logSet 1 5 20437 0 8,
  .logSet 6 5 20436 2500 10,
  .editSet 24 0 11,
  .deleteExercise 4,
  .addExercise 3 (.accepted 0) .legs,
  .deleteSet 32,
  .editSet 27 0 4,
  .logSet 10 3 20434 0 12,
  .logSet 6 4 20434 7500 5,
  .deleteSet 9,
  .editSet 5 2500 4,
  .editExercise 2 (.accepted 2) .legs,
  .deleteExercise 4,
  .deleteExercise 4,
  .logSet 12 3 20434 7500 9,
  .deleteSet 36,
  .logSet 5 5 20436 0 7,
  .logSet 10 6 20437 2500 11,
  .deleteExercise 1,
  .logSet 27 1 20434 7500 9,
  .editSet 9 0 3,
  .deleteSet 21
]

def seed1Steps : List Step := [
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .controlCharacter),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨1, 1, .chest, false⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .changed [.putExercise ⟨5, 2, .legs, false⟩],
  .changed [.putSet ⟨28, 5, 20437, 5000, 8⟩],
  .refused (.exerciseName .empty),
  .changed [.putSet ⟨15, 1, 20438, 2500, 6⟩],
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20438 0],
  .changed [.putSet ⟨11, 5, 20434, 2500, 11⟩],
  .refused .duplicateIdentifier,
  .changed [.putSet ⟨13, 5, 20434, 2500, 2⟩],
  .refused .unknownSet,
  .changed [.putSet ⟨36, 5, 20433, 2500, 5⟩],
  .changed [.putExercise ⟨2, 0, .arms, false⟩],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .duplicateExerciseName,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putExercise ⟨1, 3, .other, false⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨5, 4, .legs, false⟩],
  .changed [.putMemo 20436 0],
  .refused .unknownExercise,
  .refused .duplicateExerciseName,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putMemo 20435 1],
  .changed [],
  .changed [.putSet ⟨37, 1, 20438, 5000, 4⟩],
  .changed [],
  .refused .duplicateIdentifier,
  .refused .unknownSet,
  .changed [.putSet ⟨19, 1, 20435, 2500, 5⟩],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .changed [.putSet ⟨6, 5, 20438, 7500, 12⟩],
  .refused .unknownExercise,
  .changed [.removeExercise 2],
  .changed [.putMemo 20436 1],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨5, 4, .shoulders, false⟩],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .unknownSet,
  .changed [.putExercise ⟨4, 1, .shoulders, false⟩],
  .changed [.putSet ⟨26, 5, 20433, 2500, 3⟩],
  .changed [.putExercise ⟨5, 4, .shoulders, true⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .changed [.removeSet 26],
  .changed [.putSet ⟨30, 5, 20436, 0, 3⟩],
  .refused .unknownExercise,
  .changed [.putMemo 20436 2],
  .refused (.exerciseName .controlCharacter),
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .changed [.putSet ⟨27, 4, 20434, 5000, 9⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20433 1],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .unknownExercise,
  .changed [],
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .changed [.putSet ⟨33, 4, 20436, 5000, 3⟩],
  .refused .unknownSet,
  .refused .unknownSet,
  .changed [.putSet ⟨38, 4, 20434, 5000, 7⟩],
  .refused .duplicateIdentifier,
  .changed [.putExercise ⟨5, 0, .chest, true⟩],
  .refused .unknownSet,
  .changed [.putExercise ⟨5, 0, .chest, false⟩],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .exerciseHasSets,
  .changed [.putMemo 20437 3],
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .changed [.removeSet 19],
  .changed [.putExercise ⟨5, 4, .shoulders, false⟩],
  .refused (.exerciseName .controlCharacter),
  .changed [.putExercise ⟨5, 4, .back, false⟩],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putSet ⟨1, 5, 20437, 2500, 11⟩],
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .changed [.putExercise ⟨4, 1, .shoulders, true⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.removeSet 38],
  .changed [],
  .refused (.exerciseName .empty),
  .changed [.putSet ⟨21, 4, 20437, 5000, 1⟩],
  .refused (.exerciseName .empty),
  .changed [.removeMemo 20437],
  .refused .duplicateIdentifier,
  .refused .duplicateIdentifier,
  .refused .unknownSet,
  .refused .exerciseHasSets,
  .changed [.putExercise ⟨3, 0, .legs, false⟩],
  .refused .unknownSet,
  .changed [.putSet ⟨27, 4, 20434, 0, 4⟩],
  .changed [.putSet ⟨10, 3, 20434, 0, 12⟩],
  .refused .duplicateIdentifier,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .exerciseHasSets,
  .changed [.putSet ⟨12, 3, 20434, 7500, 9⟩],
  .changed [.removeSet 36],
  .changed [.putSet ⟨5, 5, 20436, 0, 7⟩],
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .duplicateIdentifier,
  .refused .unknownSet,
  .changed [.removeSet 21]
]

def seed1Final : Log := ⟨
  [⟨1, 3, .other, false⟩, ⟨5, 4, .back, false⟩, ⟨4, 1, .shoulders, true⟩, ⟨3, 0, .legs, false⟩],
  [⟨28, 5, 20437, 5000, 8⟩, ⟨15, 1, 20438, 2500, 6⟩, ⟨11, 5, 20434, 2500, 11⟩,
   ⟨13, 5, 20434, 2500, 2⟩, ⟨37, 1, 20438, 5000, 4⟩, ⟨6, 5, 20438, 7500, 12⟩, ⟨30, 5, 20436, 0, 3⟩,
   ⟨27, 4, 20434, 0, 4⟩, ⟨33, 4, 20436, 5000, 3⟩, ⟨1, 5, 20437, 2500, 11⟩, ⟨10, 3, 20434, 0, 12⟩,
   ⟨12, 3, 20434, 7500, 9⟩, ⟨5, 5, 20436, 0, 7⟩],
  [(20433, 1), (20435, 1), (20436, 2), (20438, 0)]⟩

/-- The model gives each step and the last log of the Swift code. -/
theorem outcomes_seed1 :
    outcomes Log.empty seed1Commands = (seed1Steps, seed1Final) := by
  decide +kernel

/-- A store that receives the changes of each accepted command holds the last log of the Swift code. -/
theorem stored_seed1 :
    stored Log.empty Log.empty seed1Commands = seed1Final := by
  decide +kernel

/-- The log of `applied` after the commands is the last log of the Swift code. -/
theorem applied_seed1 :
    applied Log.empty seed1Commands = seed1Final := by
  decide +kernel

/-- The model reads the rows of the last log as `TrainingLog.make` does. -/
theorem make_seed1Final :
    make seed1Final = none := by
  decide +kernel

/-- The log keeps the invariants of `Valid`. -/
theorem valid_seed1Final :
    Valid seed1Final := by
  constructor <;> decide +kernel

/-! ## Seed 2 of `RandomCommand.next`: 150 commands, of which the log accepted 40 and refused 110 -/

def seed2Commands : List Command := [
  .editSet 2 2500 9,
  .setExerciseArchived 3 false,
  .writeMemo 20436 (.kept 2),
  .setExerciseArchived 2 false,
  .editExercise 3 (.accepted 1) .chest,
  .logSet 36 2 20438 7500 3,
  .deleteExercise 4,
  .logSet 34 5 20438 2500 1,
  .writeMemo 20434 .nothing,
  .deleteExercise 6,
  .writeMemo 20438 (.kept 0),
  .writeMemo 20435 (.kept 4),
  .deleteExercise 5,
  .editSet 14 0 5,
  .editExercise 1 (.refused .controlCharacter) .chest,
  .logSet 19 3 20434 2500 6,
  .logSet 26 4 20435 0 2,
  .writeMemo 20438 (.kept 0),
  .deleteSet 32,
  .deleteSet 8,
  .logSet 23 2 20433 2500 6,
  .logSet 15 3 20435 7500 12,
  .setExerciseArchived 1 false,
  .editExercise 1 (.refused .controlCharacter) .chest,
  .logSet 16 5 20438 0 3,
  .logSet 1 2 20436 0 9,
  .logSet 29 4 20436 0 4,
  .logSet 28 1 20434 5000 5,
  .setExerciseArchived 3 true,
  .writeMemo 20434 (.kept 0),
  .setExerciseArchived 3 false,
  .deleteExercise 1,
  .setExerciseArchived 1 true,
  .writeMemo 20437 (.kept 4),
  .editSet 18 2500 10,
  .deleteExercise 3,
  .addExercise 3 (.accepted 1) .back,
  .setExerciseArchived 6 false,
  .setExerciseArchived 3 false,
  .editSet 13 2500 4,
  .editSet 12 2500 5,
  .deleteSet 19,
  .editExercise 6 (.accepted 2) .back,
  .editExercise 4 (.accepted 4) .other,
  .logSet 17 2 20436 0 9,
  .editSet 7 2500 2,
  .addExercise 1 (.refused .empty) .arms,
  .logSet 31 5 20437 2500 11,
  .editExercise 1 (.accepted 5) .back,
  .deleteExercise 2,
  .logSet 27 4 20438 5000 11,
  .deleteExercise 1,
  .deleteSet 27,
  .writeMemo 20437 .nothing,
  .deleteExercise 2,
  .logSet 29 1 20437 0 8,
  .editSet 4 2500 10,
  .editSet 20 5000 10,
  .editSet 38 0 9,
  .setExerciseArchived 1 true,
  .deleteSet 3,
  .editSet 7 5000 6,
  .setExerciseArchived 2 false,
  .deleteSet 10,
  .addExercise 5 (.accepted 2) .arms,
  .logSet 25 4 20434 2500 3,
  .writeMemo 20435 (.kept 1),
  .setExerciseArchived 5 false,
  .setExerciseArchived 5 true,
  .addExercise 5 (.refused .empty) .arms,
  .setExerciseArchived 6 true,
  .editExercise 6 (.accepted 2) .other,
  .writeMemo 20437 .nothing,
  .logSet 13 5 20438 0 5,
  .logSet 3 6 20435 0 8,
  .addExercise 4 (.accepted 0) .arms,
  .editExercise 2 (.refused .controlCharacter) .chest,
  .logSet 38 1 20433 7500 9,
  .logSet 10 3 20436 7500 1,
  .logSet 6 5 20434 2500 10,
  .setExerciseArchived 5 true,
  .logSet 2 5 20437 5000 12,
  .logSet 2 5 20435 5000 7,
  .deleteExercise 6,
  .addExercise 3 (.accepted 4) .abdominals,
  .deleteSet 11,
  .writeMemo 20433 (.kept 4),
  .setExerciseArchived 5 false,
  .editExercise 1 (.accepted 2) .chest,
  .writeMemo 20437 (.kept 5),
  .deleteSet 10,
  .logSet 10 4 20436 0 8,
  .editSet 21 0 1,
  .setExerciseArchived 1 false,
  .deleteSet 31,
  .logSet 36 6 20434 0 6,
  .logSet 1 2 20435 0 7,
  .deleteSet 24,
  .deleteExercise 5,
  .deleteSet 40,
  .writeMemo 20433 (.kept 1),
  .logSet 33 2 20436 0 11,
  .writeMemo 20434 (.kept 4),
  .logSet 20 5 20437 7500 5,
  .deleteExercise 6,
  .deleteSet 30,
  .deleteExercise 1,
  .logSet 4 1 20437 0 11,
  .deleteExercise 4,
  .logSet 2 6 20437 0 6,
  .addExercise 6 (.refused .empty) .shoulders,
  .logSet 30 6 20438 7500 11,
  .deleteSet 16,
  .editExercise 1 (.accepted 4) .abdominals,
  .addExercise 6 (.accepted 2) .legs,
  .writeMemo 20433 .nothing,
  .logSet 16 5 20436 7500 5,
  .editExercise 5 (.refused .empty) .arms,
  .logSet 32 3 20435 0 10,
  .logSet 10 4 20438 0 4,
  .logSet 34 4 20434 0 3,
  .addExercise 4 (.accepted 0) .arms,
  .deleteExercise 5,
  .editExercise 4 (.accepted 1) .shoulders,
  .deleteExercise 6,
  .editSet 23 0 1,
  .editExercise 1 (.refused .empty) .other,
  .editExercise 2 (.accepted 1) .abdominals,
  .logSet 31 3 20438 2500 11,
  .logSet 18 3 20437 7500 1,
  .logSet 40 3 20435 2500 11,
  .setExerciseArchived 1 false,
  .setExerciseArchived 2 false,
  .logSet 21 6 20438 0 1,
  .logSet 13 1 20434 0 5,
  .editExercise 1 (.accepted 4) .legs,
  .editSet 2 5000 8,
  .setExerciseArchived 5 true,
  .deleteExercise 6,
  .logSet 25 1 20433 7500 9,
  .setExerciseArchived 6 true,
  .deleteExercise 2,
  .logSet 38 3 20438 2500 12,
  .writeMemo 20437 (.kept 3),
  .addExercise 6 (.refused .empty) .arms,
  .deleteSet 29,
  .logSet 6 3 20435 2500 6,
  .logSet 6 2 20435 7500 11,
  .logSet 17 2 20437 5000 12,
  .deleteExercise 3
]

def seed2Steps : List Step := [
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putMemo 20436 2],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [],
  .refused .unknownExercise,
  .changed [.putMemo 20438 0],
  .changed [.putMemo 20435 4],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused (.exerciseName .controlCharacter),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .controlCharacter),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20434 0],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20437 4],
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putExercise ⟨3, 1, .back, false⟩],
  .refused .unknownExercise,
  .changed [],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.removeMemo 20437],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putExercise ⟨5, 2, .arms, false⟩],
  .refused .unknownExercise,
  .changed [.putMemo 20435 1],
  .changed [],
  .changed [.putExercise ⟨5, 2, .arms, true⟩],
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [],
  .changed [.putSet ⟨13, 5, 20438, 0, 5⟩],
  .refused .unknownExercise,
  .changed [.putExercise ⟨4, 0, .arms, false⟩],
  .refused (.exerciseName .controlCharacter),
  .refused .unknownExercise,
  .changed [.putSet ⟨10, 3, 20436, 7500, 1⟩],
  .changed [.putSet ⟨6, 5, 20434, 2500, 10⟩],
  .changed [],
  .changed [.putSet ⟨2, 5, 20437, 5000, 12⟩],
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .refused .unknownSet,
  .changed [.putMemo 20433 4],
  .changed [.putExercise ⟨5, 2, .arms, false⟩],
  .refused .unknownExercise,
  .changed [.putMemo 20437 5],
  .changed [.removeSet 10],
  .changed [.putSet ⟨10, 4, 20436, 0, 8⟩],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .exerciseHasSets,
  .refused .unknownSet,
  .changed [.putMemo 20433 1],
  .refused .unknownExercise,
  .changed [.putMemo 20434 4],
  .changed [.putSet ⟨20, 5, 20437, 7500, 5⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .duplicateExerciseName,
  .changed [.removeMemo 20433],
  .changed [.putSet ⟨16, 5, 20436, 7500, 5⟩],
  .refused (.exerciseName .empty),
  .changed [.putSet ⟨32, 3, 20435, 0, 10⟩],
  .refused .duplicateIdentifier,
  .changed [.putSet ⟨34, 4, 20434, 0, 3⟩],
  .refused .duplicateIdentifier,
  .refused .exerciseHasSets,
  .refused .duplicateExerciseName,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .changed [.putSet ⟨31, 3, 20438, 2500, 11⟩],
  .changed [.putSet ⟨18, 3, 20437, 7500, 1⟩],
  .changed [.putSet ⟨40, 3, 20435, 2500, 11⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨2, 5, 20437, 5000, 8⟩],
  .changed [.putExercise ⟨5, 2, .arms, true⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨38, 3, 20438, 2500, 12⟩],
  .changed [.putMemo 20437 3],
  .refused (.exerciseName .empty),
  .refused .unknownSet,
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .exerciseHasSets
]

def seed2Final : Log := ⟨
  [⟨3, 1, .back, false⟩, ⟨5, 2, .arms, true⟩, ⟨4, 0, .arms, false⟩],
  [⟨13, 5, 20438, 0, 5⟩, ⟨6, 5, 20434, 2500, 10⟩, ⟨2, 5, 20437, 5000, 8⟩, ⟨10, 4, 20436, 0, 8⟩,
   ⟨20, 5, 20437, 7500, 5⟩, ⟨16, 5, 20436, 7500, 5⟩, ⟨32, 3, 20435, 0, 10⟩, ⟨34, 4, 20434, 0, 3⟩,
   ⟨31, 3, 20438, 2500, 11⟩, ⟨18, 3, 20437, 7500, 1⟩, ⟨40, 3, 20435, 2500, 11⟩,
   ⟨38, 3, 20438, 2500, 12⟩],
  [(20434, 4), (20435, 1), (20436, 2), (20437, 3), (20438, 0)]⟩

/-- The model gives each step and the last log of the Swift code. -/
theorem outcomes_seed2 :
    outcomes Log.empty seed2Commands = (seed2Steps, seed2Final) := by
  decide +kernel

/-- A store that receives the changes of each accepted command holds the last log of the Swift code. -/
theorem stored_seed2 :
    stored Log.empty Log.empty seed2Commands = seed2Final := by
  decide +kernel

/-- The log of `applied` after the commands is the last log of the Swift code. -/
theorem applied_seed2 :
    applied Log.empty seed2Commands = seed2Final := by
  decide +kernel

/-- The model reads the rows of the last log as `TrainingLog.make` does. -/
theorem make_seed2Final :
    make seed2Final = none := by
  decide +kernel

/-- The log keeps the invariants of `Valid`. -/
theorem valid_seed2Final :
    Valid seed2Final := by
  constructor <;> decide +kernel

/-! ## Seed 3 of `RandomCommand.next`: 150 commands, of which the log accepted 46 and refused 104 -/

def seed3Commands : List Command := [
  .deleteSet 20,
  .editSet 26 2500 9,
  .editExercise 6 (.accepted 5) .arms,
  .editSet 25 7500 9,
  .deleteExercise 6,
  .addExercise 3 (.refused .controlCharacter) .abdominals,
  .logSet 34 6 20436 5000 5,
  .logSet 3 5 20435 0 11,
  .addExercise 4 (.refused .empty) .other,
  .editSet 29 0 5,
  .writeMemo 20437 (.kept 0),
  .writeMemo 20435 (.kept 3),
  .deleteExercise 1,
  .logSet 11 1 20438 0 6,
  .deleteSet 5,
  .setExerciseArchived 4 true,
  .addExercise 3 (.accepted 2) .shoulders,
  .deleteSet 31,
  .deleteSet 1,
  .writeMemo 20437 (.kept 5),
  .editExercise 5 (.accepted 3) .legs,
  .logSet 11 4 20435 0 3,
  .logSet 34 4 20436 0 8,
  .editSet 19 0 10,
  .logSet 31 5 20434 0 4,
  .deleteExercise 3,
  .logSet 28 4 20437 0 2,
  .writeMemo 20437 (.kept 5),
  .writeMemo 20435 .nothing,
  .setExerciseArchived 5 false,
  .addExercise 6 (.accepted 4) .other,
  .deleteSet 17,
  .editSet 6 7500 2,
  .logSet 38 6 20435 5000 8,
  .logSet 30 3 20433 7500 9,
  .deleteExercise 2,
  .logSet 22 5 20433 0 4,
  .editSet 20 0 8,
  .writeMemo 20436 (.kept 0),
  .editExercise 4 (.accepted 4) .other,
  .editSet 23 2500 1,
  .logSet 29 1 20436 5000 4,
  .editSet 30 5000 3,
  .addExercise 1 (.accepted 3) .chest,
  .logSet 38 1 20433 7500 10,
  .editSet 33 5000 9,
  .logSet 19 2 20433 2500 8,
  .editSet 8 5000 7,
  .writeMemo 20435 (.kept 2),
  .setExerciseArchived 2 false,
  .editExercise 4 (.accepted 2) .other,
  .logSet 5 1 20436 0 4,
  .addExercise 5 (.accepted 4) .legs,
  .logSet 29 5 20437 2500 1,
  .deleteSet 4,
  .editSet 15 7500 6,
  .editSet 25 0 11,
  .deleteSet 36,
  .writeMemo 20434 (.kept 1),
  .editSet 10 7500 10,
  .editSet 30 7500 12,
  .deleteExercise 2,
  .logSet 14 4 20435 7500 10,
  .addExercise 1 (.refused .empty) .arms,
  .logSet 16 4 20438 7500 8,
  .deleteExercise 3,
  .deleteExercise 1,
  .logSet 7 2 20433 7500 12,
  .editSet 17 2500 7,
  .editSet 19 5000 5,
  .logSet 24 1 20433 2500 4,
  .writeMemo 20434 (.kept 4),
  .writeMemo 20436 (.kept 0),
  .deleteSet 27,
  .editExercise 1 (.refused .controlCharacter) .arms,
  .deleteExercise 3,
  .editExercise 1 (.accepted 5) .back,
  .editSet 11 0 10,
  .addExercise 5 (.accepted 2) .arms,
  .logSet 38 6 20433 5000 8,
  .setExerciseArchived 2 true,
  .setExerciseArchived 2 true,
  .deleteExercise 4,
  .logSet 29 5 20435 2500 3,
  .addExercise 6 (.accepted 2) .legs,
  .deleteExercise 6,
  .writeMemo 20433 (.kept 2),
  .setExerciseArchived 4 false,
  .logSet 16 1 20433 2500 12,
  .editSet 31 2500 7,
  .logSet 35 3 20436 2500 1,
  .logSet 31 6 20438 7500 1,
  .logSet 39 3 20437 2500 3,
  .writeMemo 20434 .nothing,
  .logSet 13 6 20434 7500 4,
  .deleteExercise 3,
  .writeMemo 20435 .nothing,
  .writeMemo 20433 .nothing,
  .setExerciseArchived 2 false,
  .logSet 18 4 20436 7500 11,
  .editExercise 1 (.accepted 2) .shoulders,
  .writeMemo 20433 (.kept 5),
  .editSet 35 7500 6,
  .setExerciseArchived 2 false,
  .writeMemo 20436 (.kept 6),
  .logSet 25 5 20433 2500 8,
  .setExerciseArchived 4 false,
  .setExerciseArchived 6 true,
  .setExerciseArchived 1 true,
  .deleteSet 9,
  .writeMemo 20434 (.kept 3),
  .writeMemo 20433 (.kept 3),
  .editSet 13 2500 2,
  .logSet 26 5 20434 5000 11,
  .deleteSet 19,
  .logSet 19 4 20435 2500 6,
  .deleteExercise 1,
  .deleteExercise 6,
  .logSet 18 1 20433 2500 12,
  .logSet 23 4 20438 5000 1,
  .addExercise 4 (.accepted 5) .arms,
  .deleteExercise 5,
  .editSet 35 2500 2,
  .writeMemo 20433 .nothing,
  .writeMemo 20436 (.kept 0),
  .deleteSet 22,
  .setExerciseArchived 4 true,
  .deleteSet 22,
  .logSet 20 1 20434 0 2,
  .deleteExercise 4,
  .logSet 24 2 20437 2500 4,
  .addExercise 5 (.refused .empty) .shoulders,
  .logSet 4 3 20435 7500 12,
  .deleteSet 32,
  .deleteSet 40,
  .editExercise 2 (.accepted 0) .shoulders,
  .addExercise 1 (.accepted 1) .arms,
  .editSet 36 2500 4,
  .logSet 35 6 20433 0 3,
  .addExercise 1 (.refused .empty) .arms,
  .addExercise 3 (.accepted 4) .legs,
  .logSet 40 3 20433 2500 10,
  .logSet 40 5 20433 2500 9,
  .setExerciseArchived 5 true,
  .logSet 21 2 20437 2500 12,
  .logSet 37 2 20436 0 1,
  .writeMemo 20438 (.kept 0),
  .deleteExercise 2,
  .editSet 35 2500 11,
  .setExerciseArchived 6 true
]

def seed3Steps : List Step := [
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused (.exerciseName .controlCharacter),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownSet,
  .changed [.putMemo 20437 0],
  .changed [.putMemo 20435 3],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putExercise ⟨3, 2, .shoulders, false⟩],
  .refused .unknownSet,
  .refused .unknownSet,
  .changed [.putMemo 20437 5],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.removeExercise 3],
  .refused .unknownExercise,
  .changed [],
  .changed [.removeMemo 20435],
  .refused .unknownExercise,
  .changed [.putExercise ⟨6, 4, .other, false⟩],
  .refused .unknownSet,
  .refused .unknownSet,
  .changed [.putSet ⟨38, 6, 20435, 5000, 8⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putMemo 20436 0],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putExercise ⟨1, 3, .chest, false⟩],
  .refused .duplicateIdentifier,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putMemo 20435 2],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨5, 1, 20436, 0, 4⟩],
  .refused .duplicateExerciseName,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownSet,
  .changed [.putMemo 20434 1],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .changed [.putSet ⟨24, 1, 20433, 2500, 4⟩],
  .changed [.putMemo 20434 4],
  .changed [],
  .refused .unknownSet,
  .refused (.exerciseName .controlCharacter),
  .refused .unknownExercise,
  .changed [.putExercise ⟨1, 5, .back, false⟩],
  .refused .unknownSet,
  .changed [.putExercise ⟨5, 2, .arms, false⟩],
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨29, 5, 20435, 2500, 3⟩],
  .refused .duplicateIdentifier,
  .refused .exerciseHasSets,
  .changed [.putMemo 20433 2],
  .refused .unknownExercise,
  .changed [.putSet ⟨16, 1, 20433, 2500, 12⟩],
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putSet ⟨31, 6, 20438, 7500, 1⟩],
  .refused .unknownExercise,
  .changed [.removeMemo 20434],
  .changed [.putSet ⟨13, 6, 20434, 7500, 4⟩],
  .refused .unknownExercise,
  .changed [.removeMemo 20435],
  .changed [.removeMemo 20433],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .duplicateExerciseName,
  .changed [.putMemo 20433 5],
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putMemo 20436 6],
  .changed [.putSet ⟨25, 5, 20433, 2500, 8⟩],
  .refused .unknownExercise,
  .changed [.putExercise ⟨6, 4, .other, true⟩],
  .changed [.putExercise ⟨1, 5, .back, true⟩],
  .refused .unknownSet,
  .changed [.putMemo 20434 3],
  .changed [.putMemo 20433 3],
  .changed [.putSet ⟨13, 6, 20434, 2500, 2⟩],
  .changed [.putSet ⟨26, 5, 20434, 5000, 11⟩],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .exerciseHasSets,
  .changed [.putSet ⟨18, 1, 20433, 2500, 12⟩],
  .refused .unknownExercise,
  .refused .duplicateExerciseName,
  .refused .exerciseHasSets,
  .refused .unknownSet,
  .changed [.removeMemo 20433],
  .changed [.putMemo 20436 0],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putSet ⟨20, 1, 20434, 0, 2⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .refused .unknownSet,
  .changed [.putSet ⟨35, 6, 20433, 0, 3⟩],
  .refused (.exerciseName .empty),
  .refused .duplicateExerciseName,
  .refused .unknownExercise,
  .changed [.putSet ⟨40, 5, 20433, 2500, 9⟩],
  .changed [.putExercise ⟨5, 2, .arms, true⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20438 0],
  .refused .unknownExercise,
  .changed [.putSet ⟨35, 6, 20433, 2500, 11⟩],
  .changed []
]

def seed3Final : Log := ⟨
  [⟨6, 4, .other, true⟩, ⟨1, 5, .back, true⟩, ⟨5, 2, .arms, true⟩],
  [⟨38, 6, 20435, 5000, 8⟩, ⟨5, 1, 20436, 0, 4⟩, ⟨24, 1, 20433, 2500, 4⟩, ⟨29, 5, 20435, 2500, 3⟩,
   ⟨16, 1, 20433, 2500, 12⟩, ⟨31, 6, 20438, 7500, 1⟩, ⟨13, 6, 20434, 2500, 2⟩,
   ⟨25, 5, 20433, 2500, 8⟩, ⟨26, 5, 20434, 5000, 11⟩, ⟨18, 1, 20433, 2500, 12⟩,
   ⟨20, 1, 20434, 0, 2⟩, ⟨35, 6, 20433, 2500, 11⟩, ⟨40, 5, 20433, 2500, 9⟩],
  [(20434, 3), (20436, 0), (20437, 5), (20438, 0)]⟩

/-- The model gives each step and the last log of the Swift code. -/
theorem outcomes_seed3 :
    outcomes Log.empty seed3Commands = (seed3Steps, seed3Final) := by
  decide +kernel

/-- A store that receives the changes of each accepted command holds the last log of the Swift code. -/
theorem stored_seed3 :
    stored Log.empty Log.empty seed3Commands = seed3Final := by
  decide +kernel

/-- The log of `applied` after the commands is the last log of the Swift code. -/
theorem applied_seed3 :
    applied Log.empty seed3Commands = seed3Final := by
  decide +kernel

/-- The model reads the rows of the last log as `TrainingLog.make` does. -/
theorem make_seed3Final :
    make seed3Final = none := by
  decide +kernel

/-- The log keeps the invariants of `Valid`. -/
theorem valid_seed3Final :
    Valid seed3Final := by
  constructor <;> decide +kernel

/-! ## Seed 4 of `RandomCommand.next`: 150 commands, of which the log accepted 49 and refused 101 -/

def seed4Commands : List Command := [
  .logSet 12 6 20435 5000 12,
  .editSet 30 5000 11,
  .editExercise 4 (.refused .controlCharacter) .chest,
  .addExercise 6 (.refused .empty) .other,
  .editExercise 3 (.accepted 2) .other,
  .logSet 6 4 20433 5000 12,
  .deleteSet 5,
  .addExercise 2 (.accepted 5) .back,
  .editExercise 2 (.accepted 5) .legs,
  .writeMemo 20435 (.kept 1),
  .editSet 26 0 8,
  .logSet 10 4 20433 7500 6,
  .writeMemo 20438 .nothing,
  .deleteExercise 1,
  .editSet 27 7500 1,
  .addExercise 3 (.accepted 3) .chest,
  .deleteExercise 1,
  .setExerciseArchived 4 false,
  .deleteSet 4,
  .editExercise 6 (.refused .controlCharacter) .arms,
  .logSet 34 5 20438 0 1,
  .logSet 3 6 20436 7500 11,
  .editExercise 4 (.accepted 3) .arms,
  .deleteExercise 1,
  .setExerciseArchived 3 true,
  .logSet 17 4 20437 2500 4,
  .deleteSet 28,
  .writeMemo 20436 .nothing,
  .deleteSet 40,
  .addExercise 6 (.refused .empty) .legs,
  .deleteExercise 3,
  .editSet 11 5000 12,
  .deleteSet 20,
  .deleteExercise 3,
  .editExercise 3 (.accepted 2) .arms,
  .setExerciseArchived 4 false,
  .editSet 24 0 1,
  .editExercise 1 (.accepted 3) .shoulders,
  .logSet 1 2 20435 2500 5,
  .writeMemo 20436 .nothing,
  .editSet 20 2500 12,
  .deleteExercise 1,
  .deleteExercise 5,
  .setExerciseArchived 6 false,
  .addExercise 3 (.accepted 3) .arms,
  .logSet 37 3 20435 7500 11,
  .editExercise 3 (.accepted 2) .chest,
  .editExercise 2 (.refused .empty) .abdominals,
  .editExercise 5 (.refused .empty) .shoulders,
  .writeMemo 20434 .nothing,
  .editSet 18 2500 10,
  .setExerciseArchived 6 false,
  .deleteExercise 5,
  .writeMemo 20437 .nothing,
  .deleteExercise 4,
  .deleteSet 14,
  .deleteExercise 4,
  .editSet 26 5000 4,
  .editSet 40 5000 10,
  .writeMemo 20438 (.kept 4),
  .editSet 10 7500 6,
  .addExercise 5 (.refused .empty) .other,
  .writeMemo 20433 (.kept 0),
  .logSet 35 5 20437 2500 5,
  .logSet 34 1 20435 5000 8,
  .logSet 37 4 20433 7500 2,
  .addExercise 4 (.accepted 0) .legs,
  .deleteExercise 6,
  .writeMemo 20435 (.kept 2),
  .setExerciseArchived 5 true,
  .addExercise 3 (.accepted 1) .shoulders,
  .deleteExercise 6,
  .logSet 31 3 20435 5000 8,
  .editExercise 3 (.accepted 3) .other,
  .writeMemo 20438 (.kept 1),
  .setExerciseArchived 3 false,
  .logSet 10 6 20435 2500 4,
  .deleteExercise 6,
  .editExercise 3 (.accepted 5) .other,
  .setExerciseArchived 6 true,
  .logSet 18 4 20433 5000 10,
  .logSet 16 4 20437 5000 3,
  .editSet 14 2500 12,
  .logSet 2 1 20437 0 4,
  .editSet 37 7500 12,
  .writeMemo 20437 (.kept 6),
  .writeMemo 20434 .nothing,
  .editSet 8 5000 5,
  .deleteExercise 1,
  .editExercise 2 (.accepted 0) .back,
  .logSet 25 1 20438 2500 2,
  .writeMemo 20435 (.kept 0),
  .deleteExercise 5,
  .deleteExercise 3,
  .logSet 7 4 20434 0 8,
  .deleteSet 20,
  .deleteSet 10,
  .deleteExercise 3,
  .deleteSet 29,
  .writeMemo 20435 .nothing,
  .setExerciseArchived 4 true,
  .writeMemo 20436 (.kept 4),
  .deleteSet 23,
  .logSet 21 6 20438 5000 6,
  .addExercise 3 (.refused .empty) .shoulders,
  .deleteSet 14,
  .logSet 13 6 20434 0 12,
  .deleteExercise 1,
  .editExercise 6 (.refused .empty) .other,
  .deleteExercise 1,
  .deleteExercise 2,
  .deleteExercise 6,
  .writeMemo 20436 (.kept 6),
  .logSet 21 3 20438 7500 1,
  .writeMemo 20435 .nothing,
  .writeMemo 20438 (.kept 6),
  .deleteSet 2,
  .writeMemo 20435 (.kept 1),
  .logSet 1 2 20438 5000 6,
  .logSet 27 6 20435 5000 6,
  .logSet 30 1 20434 7500 10,
  .logSet 31 2 20433 2500 3,
  .writeMemo 20436 .nothing,
  .logSet 24 1 20433 2500 4,
  .writeMemo 20434 (.kept 1),
  .deleteSet 10,
  .writeMemo 20438 (.kept 5),
  .editExercise 6 (.accepted 4) .abdominals,
  .logSet 9 3 20435 5000 12,
  .writeMemo 20437 .nothing,
  .setExerciseArchived 3 false,
  .logSet 34 5 20437 5000 9,
  .logSet 17 1 20436 2500 11,
  .logSet 27 1 20438 7500 9,
  .logSet 33 3 20435 7500 12,
  .deleteExercise 5,
  .deleteExercise 6,
  .logSet 11 4 20436 7500 6,
  .logSet 11 3 20433 2500 10,
  .deleteSet 36,
  .writeMemo 20437 (.kept 1),
  .addExercise 2 (.accepted 3) .legs,
  .writeMemo 20435 (.kept 0),
  .addExercise 6 (.accepted 5) .arms,
  .deleteSet 36,
  .logSet 21 5 20435 7500 10,
  .logSet 2 6 20435 5000 2,
  .logSet 10 3 20436 0 9,
  .logSet 10 1 20434 2500 12,
  .logSet 23 1 20434 7500 2
]

def seed4Steps : List Step := [
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused (.exerciseName .controlCharacter),
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putExercise ⟨2, 5, .back, false⟩],
  .changed [.putExercise ⟨2, 5, .legs, false⟩],
  .changed [.putMemo 20435 1],
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [],
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putExercise ⟨3, 3, .chest, false⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused (.exerciseName .controlCharacter),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨3, 3, .chest, true⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [],
  .refused .unknownSet,
  .refused (.exerciseName .empty),
  .changed [.removeExercise 3],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putSet ⟨1, 2, 20435, 2500, 5⟩],
  .changed [],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨3, 3, .arms, false⟩],
  .changed [.putSet ⟨37, 3, 20435, 7500, 11⟩],
  .changed [.putExercise ⟨3, 2, .chest, false⟩],
  .refused (.exerciseName .empty),
  .refused (.exerciseName .empty),
  .changed [],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .changed [.putMemo 20438 4],
  .refused .unknownSet,
  .refused (.exerciseName .empty),
  .changed [.putMemo 20433 0],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨4, 0, .legs, false⟩],
  .refused .unknownExercise,
  .changed [.putMemo 20435 2],
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .changed [.putSet ⟨31, 3, 20435, 5000, 8⟩],
  .changed [.putExercise ⟨3, 3, .other, false⟩],
  .changed [.putMemo 20438 1],
  .changed [],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .duplicateExerciseName,
  .refused .unknownExercise,
  .changed [.putSet ⟨18, 4, 20433, 5000, 10⟩],
  .changed [.putSet ⟨16, 4, 20437, 5000, 3⟩],
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putSet ⟨37, 3, 20435, 7500, 12⟩],
  .changed [.putMemo 20437 6],
  .changed [],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .duplicateExerciseName,
  .refused .unknownExercise,
  .changed [.putMemo 20435 0],
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .changed [.putSet ⟨7, 4, 20434, 0, 8⟩],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .exerciseHasSets,
  .refused .unknownSet,
  .changed [.removeMemo 20435],
  .changed [.putExercise ⟨4, 0, .legs, true⟩],
  .changed [.putMemo 20436 4],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .unknownExercise,
  .changed [.putMemo 20436 6],
  .changed [.putSet ⟨21, 3, 20438, 7500, 1⟩],
  .changed [],
  .changed [.putMemo 20438 6],
  .refused .unknownSet,
  .changed [.putMemo 20435 1],
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .changed [.removeMemo 20436],
  .refused .unknownExercise,
  .changed [.putMemo 20434 1],
  .refused .unknownSet,
  .changed [.putMemo 20438 5],
  .refused .unknownExercise,
  .changed [.putSet ⟨9, 3, 20435, 5000, 12⟩],
  .changed [.removeMemo 20437],
  .changed [],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨33, 3, 20435, 7500, 12⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨11, 4, 20436, 7500, 6⟩],
  .refused .duplicateIdentifier,
  .refused .unknownSet,
  .changed [.putMemo 20437 1],
  .refused .duplicateIdentifier,
  .changed [.putMemo 20435 0],
  .refused .duplicateExerciseName,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨10, 3, 20436, 0, 9⟩],
  .refused .unknownExercise,
  .refused .unknownExercise
]

def seed4Final : Log := ⟨
  [⟨2, 5, .legs, false⟩, ⟨3, 3, .other, false⟩, ⟨4, 0, .legs, true⟩],
  [⟨1, 2, 20435, 2500, 5⟩, ⟨37, 3, 20435, 7500, 12⟩, ⟨31, 3, 20435, 5000, 8⟩,
   ⟨18, 4, 20433, 5000, 10⟩, ⟨16, 4, 20437, 5000, 3⟩, ⟨7, 4, 20434, 0, 8⟩, ⟨21, 3, 20438, 7500, 1⟩,
   ⟨9, 3, 20435, 5000, 12⟩, ⟨33, 3, 20435, 7500, 12⟩, ⟨11, 4, 20436, 7500, 6⟩, ⟨10, 3, 20436, 0, 9⟩],
  [(20433, 0), (20434, 1), (20435, 0), (20437, 1), (20438, 5)]⟩

/-- The model gives each step and the last log of the Swift code. -/
theorem outcomes_seed4 :
    outcomes Log.empty seed4Commands = (seed4Steps, seed4Final) := by
  decide +kernel

/-- A store that receives the changes of each accepted command holds the last log of the Swift code. -/
theorem stored_seed4 :
    stored Log.empty Log.empty seed4Commands = seed4Final := by
  decide +kernel

/-- The log of `applied` after the commands is the last log of the Swift code. -/
theorem applied_seed4 :
    applied Log.empty seed4Commands = seed4Final := by
  decide +kernel

/-- The model reads the rows of the last log as `TrainingLog.make` does. -/
theorem make_seed4Final :
    make seed4Final = none := by
  decide +kernel

/-- The log keeps the invariants of `Valid`. -/
theorem valid_seed4Final :
    Valid seed4Final := by
  constructor <;> decide +kernel

/-! ## Seed 5 of `RandomCommand.next`: 150 commands, of which the log accepted 58 and refused 92 -/

def seed5Commands : List Command := [
  .logSet 24 4 20434 2500 12,
  .writeMemo 20438 .nothing,
  .deleteSet 26,
  .editExercise 2 (.accepted 3) .chest,
  .addExercise 5 (.accepted 3) .arms,
  .writeMemo 20436 .nothing,
  .logSet 39 1 20435 7500 11,
  .addExercise 3 (.accepted 2) .back,
  .logSet 11 1 20436 7500 7,
  .logSet 17 2 20433 0 8,
  .writeMemo 20438 (.kept 0),
  .deleteExercise 6,
  .deleteExercise 4,
  .writeMemo 20433 (.kept 6),
  .logSet 21 3 20438 7500 6,
  .logSet 9 2 20433 2500 6,
  .deleteSet 16,
  .addExercise 5 (.accepted 2) .abdominals,
  .logSet 2 4 20436 2500 3,
  .deleteExercise 6,
  .editExercise 4 (.accepted 5) .back,
  .deleteSet 18,
  .writeMemo 20437 .nothing,
  .logSet 12 3 20437 5000 7,
  .setExerciseArchived 4 false,
  .logSet 23 2 20437 0 11,
  .writeMemo 20435 (.kept 2),
  .logSet 31 3 20435 7500 3,
  .editSet 14 0 8,
  .deleteSet 3,
  .editSet 8 7500 8,
  .editExercise 5 (.accepted 1) .legs,
  .logSet 24 3 20438 0 11,
  .logSet 39 5 20437 7500 2,
  .logSet 37 2 20433 0 9,
  .logSet 20 4 20434 5000 10,
  .writeMemo 20433 (.kept 1),
  .logSet 27 5 20437 5000 3,
  .logSet 35 5 20437 0 4,
  .setExerciseArchived 4 false,
  .deleteSet 29,
  .logSet 16 3 20435 0 5,
  .logSet 28 5 20435 2500 6,
  .setExerciseArchived 6 true,
  .logSet 14 3 20433 7500 6,
  .editSet 36 2500 1,
  .writeMemo 20438 .nothing,
  .logSet 9 2 20438 2500 2,
  .logSet 7 1 20434 2500 8,
  .logSet 28 1 20433 5000 2,
  .deleteExercise 6,
  .addExercise 1 (.accepted 1) .arms,
  .logSet 30 5 20437 7500 5,
  .editExercise 4 (.accepted 2) .shoulders,
  .editSet 22 0 5,
  .editSet 34 2500 4,
  .logSet 37 6 20434 5000 12,
  .addExercise 3 (.accepted 4) .back,
  .logSet 31 4 20435 2500 3,
  .logSet 39 6 20433 0 7,
  .addExercise 3 (.refused .empty) .chest,
  .setExerciseArchived 1 true,
  .logSet 38 4 20438 7500 2,
  .editExercise 2 (.refused .empty) .arms,
  .editSet 4 2500 6,
  .logSet 12 2 20437 5000 1,
  .writeMemo 20437 .nothing,
  .logSet 18 2 20433 5000 2,
  .editSet 38 7500 3,
  .writeMemo 20435 (.kept 5),
  .logSet 31 6 20435 0 6,
  .addExercise 4 (.accepted 2) .abdominals,
  .writeMemo 20436 (.kept 6),
  .addExercise 6 (.refused .empty) .back,
  .logSet 2 1 20437 5000 11,
  .addExercise 2 (.accepted 3) .back,
  .logSet 16 5 20437 5000 4,
  .writeMemo 20433 (.kept 4),
  .setExerciseArchived 3 true,
  .logSet 37 1 20433 2500 1,
  .editExercise 1 (.accepted 5) .back,
  .editSet 3 5000 7,
  .editExercise 3 (.refused .controlCharacter) .legs,
  .writeMemo 20434 (.kept 3),
  .setExerciseArchived 4 false,
  .logSet 14 1 20434 2500 10,
  .logSet 35 1 20433 2500 12,
  .editSet 33 5000 12,
  .setExerciseArchived 2 false,
  .addExercise 4 (.refused .empty) .arms,
  .setExerciseArchived 4 true,
  .deleteSet 6,
  .editExercise 5 (.accepted 5) .legs,
  .addExercise 6 (.refused .empty) .back,
  .addExercise 2 (.accepted 2) .shoulders,
  .editSet 38 2500 11,
  .setExerciseArchived 2 false,
  .editExercise 4 (.refused .controlCharacter) .legs,
  .editExercise 6 (.refused .controlCharacter) .other,
  .logSet 27 4 20437 5000 5,
  .logSet 35 2 20435 5000 1,
  .deleteExercise 1,
  .writeMemo 20435 (.kept 1),
  .logSet 36 1 20435 7500 10,
  .editSet 1 5000 6,
  .addExercise 6 (.accepted 2) .back,
  .editExercise 4 (.refused .empty) .other,
  .logSet 15 1 20438 2500 8,
  .editSet 23 0 12,
  .deleteSet 33,
  .deleteExercise 3,
  .logSet 2 2 20433 2500 6,
  .editExercise 2 (.accepted 0) .arms,
  .logSet 35 4 20437 5000 12,
  .writeMemo 20436 .nothing,
  .editSet 14 5000 11,
  .setExerciseArchived 2 true,
  .logSet 33 3 20434 7500 3,
  .deleteExercise 2,
  .logSet 7 4 20435 0 12,
  .logSet 5 2 20433 2500 12,
  .logSet 15 3 20438 2500 6,
  .writeMemo 20436 (.kept 3),
  .setExerciseArchived 5 false,
  .writeMemo 20433 (.kept 0),
  .editSet 30 2500 1,
  .logSet 5 5 20433 5000 12,
  .logSet 16 5 20437 0 1,
  .deleteExercise 5,
  .editExercise 6 (.accepted 1) .chest,
  .editSet 24 7500 7,
  .logSet 1 2 20436 0 8,
  .logSet 38 5 20434 5000 1,
  .editSet 29 0 11,
  .setExerciseArchived 1 false,
  .editSet 35 0 7,
  .writeMemo 20438 (.kept 5),
  .deleteSet 31,
  .deleteExercise 1,
  .logSet 34 3 20436 0 3,
  .editExercise 2 (.accepted 3) .abdominals,
  .editExercise 4 (.accepted 1) .chest,
  .logSet 36 4 20438 7500 6,
  .logSet 34 2 20433 7500 3,
  .logSet 11 2 20438 7500 8,
  .logSet 31 5 20435 0 2,
  .deleteExercise 2,
  .writeMemo 20438 (.kept 2),
  .deleteSet 31,
  .writeMemo 20434 (.kept 5)
]

def seed5Steps : List Step := [
  .refused .unknownExercise,
  .changed [],
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putExercise ⟨5, 3, .arms, false⟩],
  .changed [],
  .refused .unknownExercise,
  .changed [.putExercise ⟨3, 2, .back, false⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20438 0],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20433 6],
  .changed [.putSet ⟨21, 3, 20438, 7500, 6⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [],
  .changed [.putSet ⟨12, 3, 20437, 5000, 7⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20435 2],
  .changed [.putSet ⟨31, 3, 20435, 7500, 3⟩],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownSet,
  .changed [.putExercise ⟨5, 1, .legs, false⟩],
  .changed [.putSet ⟨24, 3, 20438, 0, 11⟩],
  .changed [.putSet ⟨39, 5, 20437, 7500, 2⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20433 1],
  .changed [.putSet ⟨27, 5, 20437, 5000, 3⟩],
  .changed [.putSet ⟨35, 5, 20437, 0, 4⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putSet ⟨16, 3, 20435, 0, 5⟩],
  .changed [.putSet ⟨28, 5, 20435, 2500, 6⟩],
  .refused .unknownExercise,
  .changed [.putSet ⟨14, 3, 20433, 7500, 6⟩],
  .refused .unknownSet,
  .changed [.removeMemo 20438],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .duplicateExerciseName,
  .changed [.putSet ⟨30, 5, 20437, 7500, 5⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [],
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putMemo 20435 5],
  .refused .unknownExercise,
  .refused .duplicateExerciseName,
  .changed [.putMemo 20436 6],
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .changed [.putExercise ⟨2, 3, .back, false⟩],
  .refused .duplicateIdentifier,
  .changed [.putMemo 20433 4],
  .changed [.putExercise ⟨3, 2, .back, true⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused (.exerciseName .controlCharacter),
  .changed [.putMemo 20434 3],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [],
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putExercise ⟨5, 5, .legs, false⟩],
  .refused (.exerciseName .empty),
  .refused .duplicateIdentifier,
  .refused .unknownSet,
  .changed [],
  .refused (.exerciseName .controlCharacter),
  .refused (.exerciseName .controlCharacter),
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .changed [.putMemo 20435 1],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .duplicateExerciseName,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .exerciseHasSets,
  .changed [.putSet ⟨2, 2, 20433, 2500, 6⟩],
  .changed [.putExercise ⟨2, 0, .arms, false⟩],
  .refused .unknownExercise,
  .changed [.removeMemo 20436],
  .changed [.putSet ⟨14, 3, 20433, 5000, 11⟩],
  .changed [.putExercise ⟨2, 0, .arms, true⟩],
  .changed [.putSet ⟨33, 3, 20434, 7500, 3⟩],
  .refused .exerciseHasSets,
  .refused .unknownExercise,
  .changed [.putSet ⟨5, 2, 20433, 2500, 12⟩],
  .changed [.putSet ⟨15, 3, 20438, 2500, 6⟩],
  .changed [.putMemo 20436 3],
  .changed [],
  .changed [.putMemo 20433 0],
  .changed [.putSet ⟨30, 5, 20437, 2500, 1⟩],
  .refused .duplicateIdentifier,
  .refused .duplicateIdentifier,
  .refused .exerciseHasSets,
  .refused .unknownExercise,
  .changed [.putSet ⟨24, 3, 20438, 7500, 7⟩],
  .changed [.putSet ⟨1, 2, 20436, 0, 8⟩],
  .changed [.putSet ⟨38, 5, 20434, 5000, 1⟩],
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putSet ⟨35, 5, 20437, 0, 7⟩],
  .changed [.putMemo 20438 5],
  .changed [.removeSet 31],
  .refused .unknownExercise,
  .changed [.putSet ⟨34, 3, 20436, 0, 3⟩],
  .changed [.putExercise ⟨2, 3, .abdominals, true⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .changed [.putSet ⟨11, 2, 20438, 7500, 8⟩],
  .changed [.putSet ⟨31, 5, 20435, 0, 2⟩],
  .refused .exerciseHasSets,
  .changed [.putMemo 20438 2],
  .changed [.removeSet 31],
  .changed [.putMemo 20434 5]
]

def seed5Final : Log := ⟨
  [⟨5, 5, .legs, false⟩, ⟨3, 2, .back, true⟩, ⟨2, 3, .abdominals, true⟩],
  [⟨21, 3, 20438, 7500, 6⟩, ⟨12, 3, 20437, 5000, 7⟩, ⟨24, 3, 20438, 7500, 7⟩,
   ⟨39, 5, 20437, 7500, 2⟩, ⟨27, 5, 20437, 5000, 3⟩, ⟨35, 5, 20437, 0, 7⟩, ⟨16, 3, 20435, 0, 5⟩,
   ⟨28, 5, 20435, 2500, 6⟩, ⟨14, 3, 20433, 5000, 11⟩, ⟨30, 5, 20437, 2500, 1⟩,
   ⟨2, 2, 20433, 2500, 6⟩, ⟨33, 3, 20434, 7500, 3⟩, ⟨5, 2, 20433, 2500, 12⟩,
   ⟨15, 3, 20438, 2500, 6⟩, ⟨1, 2, 20436, 0, 8⟩, ⟨38, 5, 20434, 5000, 1⟩, ⟨34, 3, 20436, 0, 3⟩,
   ⟨11, 2, 20438, 7500, 8⟩],
  [(20433, 0), (20434, 5), (20435, 1), (20436, 3), (20438, 2)]⟩

/-- The model gives each step and the last log of the Swift code. -/
theorem outcomes_seed5 :
    outcomes Log.empty seed5Commands = (seed5Steps, seed5Final) := by
  decide +kernel

/-- A store that receives the changes of each accepted command holds the last log of the Swift code. -/
theorem stored_seed5 :
    stored Log.empty Log.empty seed5Commands = seed5Final := by
  decide +kernel

/-- The log of `applied` after the commands is the last log of the Swift code. -/
theorem applied_seed5 :
    applied Log.empty seed5Commands = seed5Final := by
  decide +kernel

/-- The model reads the rows of the last log as `TrainingLog.make` does. -/
theorem make_seed5Final :
    make seed5Final = none := by
  decide +kernel

/-- The log keeps the invariants of `Valid`. -/
theorem valid_seed5Final :
    Valid seed5Final := by
  constructor <;> decide +kernel

/-! ## Seed 6 of `RandomCommand.next`: 150 commands, of which the log accepted 49 and refused 101 -/

def seed6Commands : List Command := [
  .setExerciseArchived 5 false,
  .logSet 26 4 20438 2500 1,
  .deleteExercise 3,
  .writeMemo 20433 (.kept 5),
  .logSet 11 3 20436 7500 7,
  .logSet 38 5 20437 7500 3,
  .editExercise 5 (.accepted 5) .other,
  .logSet 8 3 20435 0 3,
  .deleteSet 28,
  .addExercise 6 (.accepted 0) .abdominals,
  .logSet 35 6 20433 7500 10,
  .logSet 26 6 20435 2500 2,
  .setExerciseArchived 5 false,
  .logSet 31 2 20435 0 10,
  .deleteSet 1,
  .writeMemo 20436 .nothing,
  .deleteSet 11,
  .editExercise 1 (.accepted 4) .arms,
  .logSet 34 3 20433 2500 7,
  .logSet 8 5 20438 0 5,
  .logSet 9 4 20437 0 3,
  .editSet 5 2500 8,
  .editSet 12 2500 2,
  .logSet 26 2 20437 2500 12,
  .deleteExercise 2,
  .logSet 16 4 20438 0 6,
  .editExercise 3 (.accepted 2) .arms,
  .logSet 3 5 20434 7500 10,
  .editSet 30 0 6,
  .editExercise 3 (.accepted 4) .back,
  .deleteSet 32,
  .setExerciseArchived 4 true,
  .deleteExercise 2,
  .logSet 12 2 20433 7500 11,
  .logSet 28 6 20433 5000 4,
  .setExerciseArchived 1 true,
  .deleteExercise 1,
  .setExerciseArchived 4 true,
  .writeMemo 20434 (.kept 1),
  .editSet 4 7500 6,
  .writeMemo 20433 .nothing,
  .editSet 25 7500 9,
  .editExercise 5 (.accepted 4) .other,
  .deleteSet 23,
  .logSet 15 6 20435 7500 10,
  .writeMemo 20435 (.kept 4),
  .editExercise 2 (.refused .controlCharacter) .arms,
  .deleteExercise 4,
  .writeMemo 20436 (.kept 4),
  .deleteExercise 3,
  .editSet 11 2500 5,
  .logSet 35 4 20438 2500 10,
  .logSet 29 5 20434 7500 3,
  .deleteExercise 4,
  .editExercise 5 (.accepted 0) .shoulders,
  .logSet 26 3 20435 0 2,
  .addExercise 3 (.accepted 1) .chest,
  .editExercise 5 (.refused .empty) .back,
  .deleteExercise 3,
  .logSet 34 3 20437 7500 11,
  .setExerciseArchived 5 true,
  .editExercise 4 (.refused .controlCharacter) .back,
  .logSet 19 2 20438 2500 12,
  .writeMemo 20438 (.kept 6),
  .addExercise 5 (.accepted 3) .legs,
  .logSet 30 5 20436 5000 3,
  .logSet 18 1 20436 5000 3,
  .deleteExercise 3,
  .editExercise 5 (.refused .controlCharacter) .arms,
  .logSet 27 6 20438 2500 9,
  .addExercise 1 (.refused .empty) .shoulders,
  .addExercise 5 (.accepted 0) .arms,
  .editExercise 6 (.accepted 1) .arms,
  .logSet 4 4 20434 7500 6,
  .deleteSet 21,
  .writeMemo 20437 .nothing,
  .deleteExercise 4,
  .setExerciseArchived 4 false,
  .writeMemo 20434 (.kept 1),
  .editSet 28 5000 2,
  .deleteSet 29,
  .writeMemo 20433 .nothing,
  .writeMemo 20438 (.kept 4),
  .addExercise 2 (.accepted 3) .legs,
  .deleteExercise 3,
  .setExerciseArchived 3 false,
  .addExercise 3 (.accepted 5) .abdominals,
  .editSet 21 2500 3,
  .deleteSet 33,
  .addExercise 3 (.accepted 5) .chest,
  .deleteExercise 3,
  .deleteExercise 2,
  .deleteSet 4,
  .logSet 4 2 20434 7500 5,
  .editExercise 3 (.accepted 2) .other,
  .writeMemo 20436 (.kept 2),
  .addExercise 5 (.refused .empty) .abdominals,
  .logSet 22 3 20433 2500 3,
  .logSet 24 1 20434 7500 11,
  .deleteExercise 6,
  .logSet 15 2 20438 7500 3,
  .setExerciseArchived 5 false,
  .logSet 3 5 20436 5000 5,
  .logSet 38 4 20437 0 5,
  .writeMemo 20436 (.kept 3),
  .logSet 37 2 20434 0 10,
  .editExercise 2 (.accepted 3) .abdominals,
  .deleteSet 14,
  .writeMemo 20433 (.kept 0),
  .writeMemo 20438 (.kept 2),
  .editSet 25 5000 9,
  .editExercise 2 (.accepted 0) .legs,
  .addExercise 4 (.accepted 4) .shoulders,
  .deleteSet 1,
  .writeMemo 20434 .nothing,
  .logSet 8 5 20435 5000 2,
  .deleteExercise 1,
  .setExerciseArchived 3 true,
  .logSet 26 2 20438 7500 10,
  .addExercise 3 (.accepted 5) .abdominals,
  .editSet 10 5000 6,
  .addExercise 4 (.refused .empty) .other,
  .logSet 19 4 20438 5000 11,
  .writeMemo 20433 (.kept 5),
  .writeMemo 20437 (.kept 1),
  .logSet 39 2 20434 7500 1,
  .deleteExercise 5,
  .logSet 37 6 20433 5000 7,
  .deleteExercise 5,
  .editExercise 4 (.accepted 5) .other,
  .deleteSet 4,
  .logSet 1 3 20438 5000 6,
  .addExercise 2 (.refused .empty) .chest,
  .addExercise 3 (.accepted 4) .abdominals,
  .addExercise 6 (.refused .controlCharacter) .arms,
  .logSet 36 4 20435 7500 5,
  .setExerciseArchived 4 false,
  .deleteSet 39,
  .addExercise 1 (.accepted 2) .other,
  .editExercise 2 (.refused .empty) .chest,
  .deleteSet 27,
  .editExercise 1 (.refused .controlCharacter) .back,
  .editSet 1 7500 10,
  .setExerciseArchived 1 true,
  .setExerciseArchived 2 false,
  .logSet 23 2 20434 2500 9,
  .setExerciseArchived 5 true,
  .deleteSet 10,
  .setExerciseArchived 1 false,
  .setExerciseArchived 3 true
]

def seed6Steps : List Step := [
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20433 5],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putExercise ⟨6, 0, .abdominals, false⟩],
  .changed [.putSet ⟨35, 6, 20433, 7500, 10⟩],
  .changed [.putSet ⟨26, 6, 20435, 2500, 2⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨28, 6, 20433, 5000, 4⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20434 1],
  .refused .unknownSet,
  .changed [.removeMemo 20433],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putSet ⟨15, 6, 20435, 7500, 10⟩],
  .changed [.putMemo 20435 4],
  .refused (.exerciseName .controlCharacter),
  .refused .unknownExercise,
  .changed [.putMemo 20436 4],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨3, 1, .chest, false⟩],
  .refused (.exerciseName .empty),
  .changed [.removeExercise 3],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .controlCharacter),
  .refused .unknownExercise,
  .changed [.putMemo 20438 6],
  .changed [.putExercise ⟨5, 3, .legs, false⟩],
  .changed [.putSet ⟨30, 5, 20436, 5000, 3⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .controlCharacter),
  .changed [.putSet ⟨27, 6, 20438, 2500, 9⟩],
  .refused (.exerciseName .empty),
  .refused .duplicateIdentifier,
  .changed [.putExercise ⟨6, 1, .arms, false⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [],
  .changed [.putSet ⟨28, 6, 20433, 5000, 2⟩],
  .refused .unknownSet,
  .changed [],
  .changed [.putMemo 20438 4],
  .refused .duplicateExerciseName,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨3, 5, .abdominals, false⟩],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .duplicateIdentifier,
  .changed [.removeExercise 3],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20436 2],
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .unknownExercise,
  .changed [],
  .changed [.putSet ⟨3, 5, 20436, 5000, 5⟩],
  .refused .unknownExercise,
  .changed [.putMemo 20436 3],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putMemo 20433 0],
  .changed [.putMemo 20438 2],
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putExercise ⟨4, 4, .shoulders, false⟩],
  .refused .unknownSet,
  .changed [.removeMemo 20434],
  .changed [.putSet ⟨8, 5, 20435, 5000, 2⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨3, 5, .abdominals, false⟩],
  .refused .unknownSet,
  .refused (.exerciseName .empty),
  .changed [.putSet ⟨19, 4, 20438, 5000, 11⟩],
  .changed [.putMemo 20433 5],
  .changed [.putMemo 20437 1],
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .changed [.putSet ⟨37, 6, 20433, 5000, 7⟩],
  .refused .exerciseHasSets,
  .refused .duplicateExerciseName,
  .refused .unknownSet,
  .changed [.putSet ⟨1, 3, 20438, 5000, 6⟩],
  .refused (.exerciseName .empty),
  .refused .duplicateIdentifier,
  .refused (.exerciseName .controlCharacter),
  .changed [.putSet ⟨36, 4, 20435, 7500, 5⟩],
  .changed [],
  .refused .unknownSet,
  .changed [.putExercise ⟨1, 2, .other, false⟩],
  .refused (.exerciseName .empty),
  .changed [.removeSet 27],
  .refused (.exerciseName .controlCharacter),
  .changed [.putSet ⟨1, 3, 20438, 7500, 10⟩],
  .changed [.putExercise ⟨1, 2, .other, true⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨5, 3, .legs, true⟩],
  .refused .unknownSet,
  .changed [.putExercise ⟨1, 2, .other, false⟩],
  .changed [.putExercise ⟨3, 5, .abdominals, true⟩]
]

def seed6Final : Log := ⟨
  [⟨6, 1, .arms, false⟩, ⟨5, 3, .legs, true⟩, ⟨4, 4, .shoulders, false⟩, ⟨3, 5, .abdominals, true⟩,
   ⟨1, 2, .other, false⟩],
  [⟨35, 6, 20433, 7500, 10⟩, ⟨26, 6, 20435, 2500, 2⟩, ⟨28, 6, 20433, 5000, 2⟩,
   ⟨15, 6, 20435, 7500, 10⟩, ⟨30, 5, 20436, 5000, 3⟩, ⟨3, 5, 20436, 5000, 5⟩,
   ⟨8, 5, 20435, 5000, 2⟩, ⟨19, 4, 20438, 5000, 11⟩, ⟨37, 6, 20433, 5000, 7⟩,
   ⟨1, 3, 20438, 7500, 10⟩, ⟨36, 4, 20435, 7500, 5⟩],
  [(20433, 5), (20435, 4), (20436, 3), (20437, 1), (20438, 2)]⟩

/-- The model gives each step and the last log of the Swift code. -/
theorem outcomes_seed6 :
    outcomes Log.empty seed6Commands = (seed6Steps, seed6Final) := by
  decide +kernel

/-- A store that receives the changes of each accepted command holds the last log of the Swift code. -/
theorem stored_seed6 :
    stored Log.empty Log.empty seed6Commands = seed6Final := by
  decide +kernel

/-- The log of `applied` after the commands is the last log of the Swift code. -/
theorem applied_seed6 :
    applied Log.empty seed6Commands = seed6Final := by
  decide +kernel

/-- The model reads the rows of the last log as `TrainingLog.make` does. -/
theorem make_seed6Final :
    make seed6Final = none := by
  decide +kernel

/-- The log keeps the invariants of `Valid`. -/
theorem valid_seed6Final :
    Valid seed6Final := by
  constructor <;> decide +kernel

/-! ## Seed 7 of `RandomCommand.next`: 150 commands, of which the log accepted 46 and refused 104 -/

def seed7Commands : List Command := [
  .deleteExercise 3,
  .logSet 22 4 20438 7500 11,
  .logSet 35 3 20437 0 5,
  .addExercise 3 (.accepted 4) .legs,
  .editExercise 6 (.refused .empty) .arms,
  .deleteSet 33,
  .setExerciseArchived 4 true,
  .logSet 7 3 20435 7500 5,
  .logSet 3 6 20438 2500 1,
  .logSet 3 6 20435 5000 9,
  .deleteSet 28,
  .addExercise 5 (.accepted 4) .shoulders,
  .writeMemo 20433 (.kept 3),
  .logSet 5 6 20438 5000 3,
  .logSet 29 6 20438 2500 5,
  .logSet 30 6 20434 7500 8,
  .setExerciseArchived 6 false,
  .addExercise 3 (.accepted 3) .chest,
  .logSet 16 5 20433 5000 11,
  .deleteExercise 4,
  .setExerciseArchived 4 true,
  .logSet 9 1 20435 5000 4,
  .logSet 29 3 20435 5000 12,
  .editExercise 4 (.accepted 5) .shoulders,
  .logSet 12 5 20436 2500 4,
  .logSet 10 5 20433 7500 3,
  .logSet 27 6 20437 2500 7,
  .deleteSet 29,
  .setExerciseArchived 3 false,
  .setExerciseArchived 3 true,
  .setExerciseArchived 1 false,
  .deleteSet 2,
  .editSet 2 7500 1,
  .deleteExercise 6,
  .writeMemo 20437 (.kept 4),
  .writeMemo 20433 (.kept 6),
  .writeMemo 20434 (.kept 5),
  .setExerciseArchived 4 true,
  .setExerciseArchived 5 true,
  .editExercise 1 (.refused .empty) .shoulders,
  .setExerciseArchived 5 false,
  .editExercise 1 (.accepted 2) .other,
  .editSet 29 2500 2,
  .editSet 16 0 10,
  .setExerciseArchived 5 true,
  .addExercise 3 (.accepted 2) .legs,
  .logSet 5 2 20433 0 11,
  .logSet 35 4 20434 2500 4,
  .deleteSet 1,
  .logSet 14 2 20438 7500 7,
  .editSet 10 0 8,
  .logSet 34 2 20434 5000 9,
  .setExerciseArchived 2 true,
  .deleteExercise 4,
  .logSet 9 4 20434 5000 2,
  .editExercise 2 (.accepted 4) .back,
  .deleteExercise 2,
  .editExercise 2 (.refused .empty) .back,
  .setExerciseArchived 6 false,
  .deleteSet 1,
  .editExercise 6 (.refused .empty) .other,
  .deleteExercise 5,
  .editExercise 1 (.accepted 1) .shoulders,
  .addExercise 4 (.accepted 2) .legs,
  .deleteExercise 3,
  .writeMemo 20437 (.kept 6),
  .logSet 32 2 20434 2500 5,
  .logSet 39 4 20434 2500 4,
  .deleteSet 13,
  .deleteSet 10,
  .deleteExercise 3,
  .logSet 28 3 20435 2500 7,
  .setExerciseArchived 1 false,
  .deleteExercise 1,
  .logSet 38 6 20436 7500 1,
  .logSet 14 3 20436 2500 8,
  .editExercise 4 (.accepted 4) .legs,
  .logSet 13 4 20437 5000 11,
  .deleteSet 34,
  .writeMemo 20435 (.kept 6),
  .logSet 12 6 20437 0 6,
  .logSet 38 5 20437 0 4,
  .editExercise 1 (.refused .empty) .legs,
  .editSet 28 5000 12,
  .setExerciseArchived 5 false,
  .deleteExercise 1,
  .setExerciseArchived 6 false,
  .logSet 10 5 20437 0 8,
  .editExercise 6 (.accepted 1) .chest,
  .editExercise 2 (.refused .empty) .other,
  .addExercise 5 (.accepted 3) .other,
  .logSet 32 3 20438 7500 12,
  .writeMemo 20433 .nothing,
  .setExerciseArchived 5 false,
  .deleteExercise 1,
  .logSet 16 5 20436 5000 12,
  .deleteSet 15,
  .editSet 24 2500 1,
  .writeMemo 20435 (.kept 3),
  .writeMemo 20437 (.kept 3),
  .logSet 9 2 20435 0 3,
  .deleteSet 26,
  .logSet 2 1 20435 2500 9,
  .writeMemo 20436 (.kept 1),
  .editSet 35 5000 2,
  .logSet 3 1 20437 5000 9,
  .deleteExercise 2,
  .deleteExercise 4,
  .editSet 12 0 2,
  .logSet 19 2 20433 5000 1,
  .editExercise 1 (.refused .empty) .other,
  .editSet 8 0 6,
  .editExercise 6 (.refused .empty) .legs,
  .deleteExercise 1,
  .setExerciseArchived 4 false,
  .editExercise 3 (.accepted 4) .shoulders,
  .addExercise 2 (.accepted 0) .chest,
  .writeMemo 20435 (.kept 0),
  .logSet 40 5 20433 7500 5,
  .logSet 21 2 20435 0 9,
  .deleteExercise 1,
  .setExerciseArchived 2 true,
  .addExercise 2 (.accepted 3) .legs,
  .logSet 9 2 20438 2500 2,
  .deleteExercise 1,
  .editExercise 6 (.accepted 2) .chest,
  .logSet 4 6 20438 0 4,
  .logSet 7 4 20433 7500 5,
  .editSet 18 7500 6,
  .writeMemo 20434 (.kept 6),
  .writeMemo 20437 (.kept 0),
  .deleteExercise 6,
  .logSet 33 6 20435 7500 4,
  .logSet 1 2 20438 0 10,
  .addExercise 5 (.accepted 5) .arms,
  .writeMemo 20433 .nothing,
  .addExercise 1 (.accepted 5) .chest,
  .editSet 9 7500 11,
  .setExerciseArchived 2 true,
  .logSet 35 2 20437 0 9,
  .editSet 17 0 5,
  .editExercise 3 (.refused .controlCharacter) .chest,
  .editExercise 1 (.accepted 1) .arms,
  .logSet 20 3 20433 2500 12,
  .logSet 38 5 20438 5000 11,
  .editExercise 1 (.accepted 0) .abdominals,
  .editSet 21 0 3,
  .editSet 12 0 10,
  .addExercise 1 (.refused .empty) .legs,
  .deleteSet 26
]

def seed7Steps : List Step := [
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨3, 4, .legs, false⟩],
  .refused (.exerciseName .empty),
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putSet ⟨7, 3, 20435, 7500, 5⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .duplicateExerciseName,
  .changed [.putMemo 20433 3],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨29, 3, 20435, 5000, 12⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.removeSet 29],
  .changed [],
  .changed [.putExercise ⟨3, 4, .legs, true⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putMemo 20437 4],
  .changed [.putMemo 20433 6],
  .changed [.putMemo 20434 5],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨4, 2, .legs, false⟩],
  .refused .exerciseHasSets,
  .changed [.putMemo 20437 6],
  .refused .unknownExercise,
  .changed [.putSet ⟨39, 4, 20434, 2500, 4⟩],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .exerciseHasSets,
  .changed [.putSet ⟨28, 3, 20435, 2500, 7⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨14, 3, 20436, 2500, 8⟩],
  .refused .duplicateExerciseName,
  .changed [.putSet ⟨13, 4, 20437, 5000, 11⟩],
  .refused .unknownSet,
  .changed [.putMemo 20435 6],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .changed [.putSet ⟨28, 3, 20435, 5000, 12⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .changed [.putExercise ⟨5, 3, .other, false⟩],
  .changed [.putSet ⟨32, 3, 20438, 7500, 12⟩],
  .changed [.removeMemo 20433],
  .changed [],
  .refused .unknownExercise,
  .changed [.putSet ⟨16, 5, 20436, 5000, 12⟩],
  .refused .unknownSet,
  .refused .unknownSet,
  .changed [.putMemo 20435 3],
  .changed [.putMemo 20437 3],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putMemo 20436 1],
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .refused .unknownSet,
  .refused (.exerciseName .empty),
  .refused .unknownExercise,
  .changed [],
  .changed [.putExercise ⟨3, 4, .shoulders, true⟩],
  .changed [.putExercise ⟨2, 0, .chest, false⟩],
  .changed [.putMemo 20435 0],
  .changed [.putSet ⟨40, 5, 20433, 7500, 5⟩],
  .changed [.putSet ⟨21, 2, 20435, 0, 9⟩],
  .refused .unknownExercise,
  .changed [.putExercise ⟨2, 0, .chest, true⟩],
  .refused .duplicateIdentifier,
  .changed [.putSet ⟨9, 2, 20438, 2500, 2⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .refused .unknownSet,
  .changed [.putMemo 20434 6],
  .changed [.putMemo 20437 0],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨1, 2, 20438, 0, 10⟩],
  .refused .duplicateIdentifier,
  .changed [],
  .changed [.putExercise ⟨1, 5, .chest, false⟩],
  .changed [.putSet ⟨9, 2, 20438, 7500, 11⟩],
  .changed [],
  .changed [.putSet ⟨35, 2, 20437, 0, 9⟩],
  .refused .unknownSet,
  .refused (.exerciseName .controlCharacter),
  .changed [.putExercise ⟨1, 1, .arms, false⟩],
  .changed [.putSet ⟨20, 3, 20433, 2500, 12⟩],
  .changed [.putSet ⟨38, 5, 20438, 5000, 11⟩],
  .refused .duplicateExerciseName,
  .changed [.putSet ⟨21, 2, 20435, 0, 3⟩],
  .refused .unknownSet,
  .refused (.exerciseName .empty),
  .refused .unknownSet
]

def seed7Final : Log := ⟨
  [⟨3, 4, .shoulders, true⟩, ⟨4, 2, .legs, false⟩, ⟨5, 3, .other, false⟩, ⟨2, 0, .chest, true⟩,
   ⟨1, 1, .arms, false⟩],
  [⟨7, 3, 20435, 7500, 5⟩, ⟨39, 4, 20434, 2500, 4⟩, ⟨28, 3, 20435, 5000, 12⟩,
   ⟨14, 3, 20436, 2500, 8⟩, ⟨13, 4, 20437, 5000, 11⟩, ⟨32, 3, 20438, 7500, 12⟩,
   ⟨16, 5, 20436, 5000, 12⟩, ⟨40, 5, 20433, 7500, 5⟩, ⟨21, 2, 20435, 0, 3⟩, ⟨9, 2, 20438, 7500, 11⟩,
   ⟨1, 2, 20438, 0, 10⟩, ⟨35, 2, 20437, 0, 9⟩, ⟨20, 3, 20433, 2500, 12⟩, ⟨38, 5, 20438, 5000, 11⟩],
  [(20434, 6), (20435, 0), (20436, 1), (20437, 0)]⟩

/-- The model gives each step and the last log of the Swift code. -/
theorem outcomes_seed7 :
    outcomes Log.empty seed7Commands = (seed7Steps, seed7Final) := by
  decide +kernel

/-- A store that receives the changes of each accepted command holds the last log of the Swift code. -/
theorem stored_seed7 :
    stored Log.empty Log.empty seed7Commands = seed7Final := by
  decide +kernel

/-- The log of `applied` after the commands is the last log of the Swift code. -/
theorem applied_seed7 :
    applied Log.empty seed7Commands = seed7Final := by
  decide +kernel

/-- The model reads the rows of the last log as `TrainingLog.make` does. -/
theorem make_seed7Final :
    make seed7Final = none := by
  decide +kernel

/-- The log keeps the invariants of `Valid`. -/
theorem valid_seed7Final :
    Valid seed7Final := by
  constructor <;> decide +kernel

/-! ## Seed 8 of `RandomCommand.next`: 150 commands, of which the log accepted 57 and refused 93 -/

def seed8Commands : List Command := [
  .deleteExercise 6,
  .logSet 38 3 20435 0 9,
  .logSet 15 2 20438 0 5,
  .addExercise 4 (.accepted 4) .back,
  .logSet 24 3 20433 5000 2,
  .editSet 6 2500 11,
  .addExercise 3 (.accepted 5) .abdominals,
  .logSet 29 2 20433 5000 11,
  .deleteSet 32,
  .deleteSet 22,
  .editSet 30 5000 3,
  .editSet 6 2500 12,
  .logSet 14 5 20433 5000 11,
  .writeMemo 20438 .nothing,
  .writeMemo 20435 .nothing,
  .editSet 6 5000 1,
  .editSet 24 7500 2,
  .editSet 16 7500 6,
  .editExercise 5 (.accepted 0) .legs,
  .logSet 29 3 20437 0 4,
  .logSet 13 6 20434 7500 12,
  .writeMemo 20438 (.kept 0),
  .deleteExercise 4,
  .writeMemo 20435 (.kept 4),
  .editSet 40 0 9,
  .deleteSet 30,
  .deleteExercise 4,
  .logSet 30 1 20438 5000 12,
  .editSet 8 7500 10,
  .logSet 9 3 20438 0 10,
  .setExerciseArchived 1 true,
  .deleteExercise 6,
  .deleteSet 15,
  .writeMemo 20436 .nothing,
  .logSet 21 6 20433 5000 10,
  .deleteExercise 3,
  .logSet 6 2 20435 2500 12,
  .deleteExercise 2,
  .deleteSet 9,
  .logSet 15 2 20433 2500 11,
  .writeMemo 20433 (.kept 2),
  .logSet 39 5 20436 5000 9,
  .writeMemo 20434 .nothing,
  .logSet 5 1 20438 2500 1,
  .deleteSet 30,
  .logSet 17 2 20433 7500 1,
  .editSet 23 0 12,
  .logSet 40 2 20438 7500 9,
  .logSet 29 4 20438 5000 7,
  .logSet 4 3 20435 7500 5,
  .addExercise 5 (.accepted 5) .other,
  .logSet 17 4 20433 7500 7,
  .editSet 38 2500 2,
  .addExercise 2 (.accepted 3) .arms,
  .logSet 31 5 20436 5000 4,
  .logSet 9 2 20436 2500 2,
  .addExercise 1 (.accepted 1) .other,
  .logSet 36 6 20434 0 7,
  .writeMemo 20436 .nothing,
  .addExercise 4 (.accepted 5) .abdominals,
  .logSet 30 1 20437 5000 2,
  .editSet 29 7500 11,
  .editExercise 5 (.accepted 2) .other,
  .logSet 6 5 20437 2500 4,
  .deleteExercise 6,
  .addExercise 2 (.accepted 4) .shoulders,
  .editSet 1 5000 12,
  .writeMemo 20436 (.kept 6),
  .setExerciseArchived 4 false,
  .setExerciseArchived 3 false,
  .deleteSet 26,
  .editExercise 3 (.accepted 4) .abdominals,
  .logSet 26 3 20433 2500 5,
  .logSet 22 6 20435 0 6,
  .logSet 29 6 20433 5000 4,
  .deleteSet 15,
  .addExercise 1 (.accepted 4) .back,
  .editExercise 3 (.accepted 1) .arms,
  .logSet 23 4 20434 5000 7,
  .writeMemo 20433 (.kept 4),
  .setExerciseArchived 5 true,
  .editExercise 3 (.accepted 2) .shoulders,
  .logSet 4 4 20433 7500 5,
  .setExerciseArchived 1 false,
  .editSet 22 7500 3,
  .deleteExercise 3,
  .logSet 27 1 20436 7500 5,
  .writeMemo 20438 (.kept 1),
  .logSet 7 1 20434 2500 3,
  .logSet 5 2 20434 5000 8,
  .editSet 34 2500 9,
  .logSet 33 1 20436 0 1,
  .logSet 3 2 20435 2500 3,
  .editExercise 4 (.accepted 1) .back,
  .deleteSet 34,
  .deleteSet 18,
  .deleteSet 15,
  .setExerciseArchived 1 true,
  .setExerciseArchived 5 false,
  .logSet 39 6 20433 5000 10,
  .logSet 35 6 20436 2500 6,
  .writeMemo 20435 (.kept 0),
  .editExercise 4 (.accepted 1) .shoulders,
  .deleteSet 39,
  .logSet 7 2 20436 2500 11,
  .setExerciseArchived 2 true,
  .logSet 18 2 20436 5000 2,
  .logSet 2 5 20435 5000 11,
  .editExercise 3 (.accepted 5) .shoulders,
  .logSet 37 3 20433 2500 7,
  .logSet 9 4 20437 2500 10,
  .logSet 28 4 20436 2500 9,
  .deleteExercise 3,
  .editExercise 4 (.accepted 5) .abdominals,
  .writeMemo 20433 (.kept 0),
  .logSet 16 4 20433 0 1,
  .writeMemo 20437 (.kept 2),
  .setExerciseArchived 5 true,
  .logSet 2 1 20437 5000 1,
  .logSet 39 1 20434 5000 10,
  .logSet 1 2 20436 0 8,
  .deleteSet 1,
  .writeMemo 20437 (.kept 5),
  .setExerciseArchived 5 false,
  .setExerciseArchived 5 false,
  .logSet 8 4 20434 7500 11,
  .editSet 30 0 12,
  .deleteSet 3,
  .writeMemo 20433 (.kept 1),
  .deleteSet 28,
  .logSet 14 1 20435 5000 12,
  .editSet 6 0 1,
  .addExercise 1 (.refused .empty) .arms,
  .deleteSet 38,
  .editExercise 4 (.accepted 2) .arms,
  .editSet 20 5000 10,
  .logSet 9 3 20433 7500 3,
  .logSet 21 3 20433 0 1,
  .setExerciseArchived 2 false,
  .logSet 39 6 20438 2500 11,
  .writeMemo 20434 (.kept 4),
  .logSet 23 4 20437 2500 11,
  .logSet 24 1 20438 0 11,
  .deleteExercise 2,
  .writeMemo 20434 .nothing,
  .deleteExercise 3,
  .setExerciseArchived 2 true,
  .addExercise 6 (.accepted 2) .chest,
  .addExercise 3 (.accepted 3) .arms,
  .logSet 39 5 20434 2500 2
]

def seed8Steps : List Step := [
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putExercise ⟨4, 4, .back, false⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putExercise ⟨3, 5, .abdominals, false⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [],
  .changed [],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [.putSet ⟨29, 3, 20437, 0, 4⟩],
  .refused .unknownExercise,
  .changed [.putMemo 20438 0],
  .changed [.removeExercise 4],
  .changed [.putMemo 20435 4],
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putSet ⟨9, 3, 20438, 0, 10⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [],
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.removeSet 9],
  .refused .unknownExercise,
  .changed [.putMemo 20433 2],
  .refused .unknownExercise,
  .changed [],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨4, 3, 20435, 7500, 5⟩],
  .refused .duplicateExerciseName,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.putExercise ⟨2, 3, .arms, false⟩],
  .refused .unknownExercise,
  .changed [.putSet ⟨9, 2, 20436, 2500, 2⟩],
  .changed [.putExercise ⟨1, 1, .other, false⟩],
  .refused .unknownExercise,
  .changed [],
  .refused .duplicateExerciseName,
  .changed [.putSet ⟨30, 1, 20437, 5000, 2⟩],
  .changed [.putSet ⟨29, 3, 20437, 7500, 11⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .duplicateIdentifier,
  .refused .unknownSet,
  .changed [.putMemo 20436 6],
  .refused .unknownExercise,
  .changed [],
  .refused .unknownSet,
  .changed [.putExercise ⟨3, 4, .abdominals, false⟩],
  .changed [.putSet ⟨26, 3, 20433, 2500, 5⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .duplicateIdentifier,
  .refused .duplicateExerciseName,
  .refused .unknownExercise,
  .changed [.putMemo 20433 4],
  .refused .unknownExercise,
  .changed [.putExercise ⟨3, 2, .shoulders, false⟩],
  .refused .unknownExercise,
  .changed [],
  .refused .unknownSet,
  .refused .exerciseHasSets,
  .changed [.putSet ⟨27, 1, 20436, 7500, 5⟩],
  .changed [.putMemo 20438 1],
  .changed [.putSet ⟨7, 1, 20434, 2500, 3⟩],
  .changed [.putSet ⟨5, 2, 20434, 5000, 8⟩],
  .refused .unknownSet,
  .changed [.putSet ⟨33, 1, 20436, 0, 1⟩],
  .changed [.putSet ⟨3, 2, 20435, 2500, 3⟩],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .unknownSet,
  .refused .unknownSet,
  .changed [.putExercise ⟨1, 1, .other, true⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putMemo 20435 0],
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .duplicateIdentifier,
  .changed [.putExercise ⟨2, 3, .arms, true⟩],
  .changed [.putSet ⟨18, 2, 20436, 5000, 2⟩],
  .refused .unknownExercise,
  .changed [.putExercise ⟨3, 5, .shoulders, false⟩],
  .changed [.putSet ⟨37, 3, 20433, 2500, 7⟩],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .exerciseHasSets,
  .refused .unknownExercise,
  .changed [.putMemo 20433 0],
  .refused .unknownExercise,
  .changed [.putMemo 20437 2],
  .refused .unknownExercise,
  .changed [.putSet ⟨2, 1, 20437, 5000, 1⟩],
  .changed [.putSet ⟨39, 1, 20434, 5000, 10⟩],
  .changed [.putSet ⟨1, 2, 20436, 0, 8⟩],
  .changed [.removeSet 1],
  .changed [.putMemo 20437 5],
  .refused .unknownExercise,
  .refused .unknownExercise,
  .refused .unknownExercise,
  .changed [.putSet ⟨30, 1, 20437, 0, 12⟩],
  .changed [.removeSet 3],
  .changed [.putMemo 20433 1],
  .refused .unknownSet,
  .changed [.putSet ⟨14, 1, 20435, 5000, 12⟩],
  .refused .unknownSet,
  .refused (.exerciseName .empty),
  .refused .unknownSet,
  .refused .unknownExercise,
  .refused .unknownSet,
  .refused .duplicateIdentifier,
  .changed [.putSet ⟨21, 3, 20433, 0, 1⟩],
  .changed [.putExercise ⟨2, 3, .arms, false⟩],
  .refused .unknownExercise,
  .changed [.putMemo 20434 4],
  .refused .unknownExercise,
  .changed [.putSet ⟨24, 1, 20438, 0, 11⟩],
  .refused .exerciseHasSets,
  .changed [.removeMemo 20434],
  .refused .exerciseHasSets,
  .changed [.putExercise ⟨2, 3, .arms, true⟩],
  .changed [.putExercise ⟨6, 2, .chest, false⟩],
  .refused .duplicateIdentifier,
  .refused .unknownExercise
]

def seed8Final : Log := ⟨
  [⟨3, 5, .shoulders, false⟩, ⟨2, 3, .arms, true⟩, ⟨1, 1, .other, true⟩, ⟨6, 2, .chest, false⟩],
  [⟨29, 3, 20437, 7500, 11⟩, ⟨4, 3, 20435, 7500, 5⟩, ⟨9, 2, 20436, 2500, 2⟩, ⟨30, 1, 20437, 0, 12⟩,
   ⟨26, 3, 20433, 2500, 5⟩, ⟨27, 1, 20436, 7500, 5⟩, ⟨7, 1, 20434, 2500, 3⟩, ⟨5, 2, 20434, 5000, 8⟩,
   ⟨33, 1, 20436, 0, 1⟩, ⟨18, 2, 20436, 5000, 2⟩, ⟨37, 3, 20433, 2500, 7⟩, ⟨2, 1, 20437, 5000, 1⟩,
   ⟨39, 1, 20434, 5000, 10⟩, ⟨14, 1, 20435, 5000, 12⟩, ⟨21, 3, 20433, 0, 1⟩, ⟨24, 1, 20438, 0, 11⟩],
  [(20433, 1), (20435, 0), (20436, 6), (20437, 5), (20438, 1)]⟩

/-- The model gives each step and the last log of the Swift code. -/
theorem outcomes_seed8 :
    outcomes Log.empty seed8Commands = (seed8Steps, seed8Final) := by
  decide +kernel

/-- A store that receives the changes of each accepted command holds the last log of the Swift code. -/
theorem stored_seed8 :
    stored Log.empty Log.empty seed8Commands = seed8Final := by
  decide +kernel

/-- The log of `applied` after the commands is the last log of the Swift code. -/
theorem applied_seed8 :
    applied Log.empty seed8Commands = seed8Final := by
  decide +kernel

/-- The model reads the rows of the last log as `TrainingLog.make` does. -/
theorem make_seed8Final :
    make seed8Final = none := by
  decide +kernel

/-- The log keeps the invariants of `Valid`. -/
theorem valid_seed8Final :
    Valid seed8Final := by
  constructor <;> decide +kernel

/-! ## A hand-written sequence: 63 commands, of which the log accepted 40 and refused 23 -/

def handWrittenCommands : List Command := [
  .addExercise 5 (.accepted 6) .abdominals,
  .logSet 5 5 20766 0 30,
  .writeMemo 0 (.kept 7),
  .replaceAll ⟨[], [], []⟩,
  .deleteSet 5,
  .deleteExercise 5,
  .writeMemo 0 .nothing,
  .replaceAll ⟨[⟨7, 0, .back, false⟩, ⟨8, 1, .legs, true⟩], [⟨8, 7, (-1), 0, 12⟩, ⟨9, 8, 20766, 14000, 5⟩], [((-1), 8), (20766, 9)]⟩,
  .replaceAll ⟨[⟨7, 0, .back, false⟩, ⟨8, 1, .legs, true⟩], [⟨8, 7, (-1), 0, 12⟩, ⟨9, 8, 20766, 14000, 5⟩], [((-1), 8), (20766, 9)]⟩,
  .logSet 2 7 20766 2000 5,
  .logSet 8 7 20766 2000 5,
  .logSet 3 5 20766 2000 5,
  .deleteSet 8,
  .editExercise 7 (.accepted 1) .back,
  .setExerciseArchived 8 false,
  .addExercise 1 (.accepted 4) .chest,
  .addExercise 2 (.accepted 5) .legs,
  .addExercise 2 (.accepted 0) .back,
  .addExercise 3 (.accepted 4) .arms,
  .addExercise 1 (.refused .empty) .other,
  .addExercise 3 (.refused .tooLong) .other,
  .editExercise 3 (.refused .tooLong) .other,
  .addExercise 3 (.refused .controlCharacter) .other,
  .addExercise 3 (.accepted 7) .abdominals,
  .addExercise 4 (.accepted 3) .shoulders,
  .editExercise 3 (.accepted 3) .abdominals,
  .editExercise 4 (.accepted 3) .shoulders,
  .editExercise 4 (.accepted 3) .arms,
  .editExercise 4 (.accepted 6) .abdominals,
  .editExercise 9 (.accepted 3) .other,
  .editExercise 9 (.refused .empty) .other,
  .setExerciseArchived 2 true,
  .setExerciseArchived 2 true,
  .setExerciseArchived 2 false,
  .setExerciseArchived 9 true,
  .logSet 1 1 20766 6000 10,
  .logSet 1 2 20766 0 1,
  .logSet 1 9 20766 0 1,
  .logSet 3 1 (-25567) 99999 999,
  .logSet 4 2 84370 1 1,
  .logSet 5 2 (-1) 0 12,
  .editSet 1 6250 8,
  .editSet 1 6250 8,
  .editSet 1 6250 9,
  .editSet 6 0 1,
  .deleteExercise 1,
  .deleteExercise 9,
  .deleteSet 6,
  .deleteSet 1,
  .deleteSet 3,
  .deleteExercise 1,
  .addExercise 1 (.accepted 4) .chest,
  .logSet 1 1 20766 6000 10,
  .writeMemo (-25567) (.kept 10),
  .writeMemo 0 (.kept 3),
  .writeMemo 84370 (.kept 8),
  .writeMemo (-25567) (.kept 10),
  .writeMemo 0 (.kept 3),
  .writeMemo 20766 (.kept 11),
  .writeMemo (-1) .nothing,
  .writeMemo (-1) .nothing,
  .writeMemo 20766 (.refused .controlCharacter),
  .writeMemo 20766 (.refused .tooLong)
]

def handWrittenSteps : List Step := [
  .changed [.putExercise ⟨5, 6, .abdominals, false⟩],
  .changed [.putSet ⟨5, 5, 20766, 0, 30⟩],
  .changed [.putMemo 0 7],
  .changed [.replaceAll ⟨[], [], []⟩],
  .refused .unknownSet,
  .refused .unknownExercise,
  .changed [],
  .changed [.replaceAll ⟨[⟨7, 0, .back, false⟩, ⟨8, 1, .legs, true⟩], [⟨8, 7, (-1), 0, 12⟩, ⟨9, 8, 20766, 14000, 5⟩], [((-1), 8), (20766, 9)]⟩],
  .changed [.replaceAll ⟨[⟨7, 0, .back, false⟩, ⟨8, 1, .legs, true⟩], [⟨8, 7, (-1), 0, 12⟩, ⟨9, 8, 20766, 14000, 5⟩], [((-1), 8), (20766, 9)]⟩],
  .changed [.putSet ⟨2, 7, 20766, 2000, 5⟩],
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .changed [.removeSet 8],
  .refused .duplicateExerciseName,
  .changed [.putExercise ⟨8, 1, .legs, false⟩],
  .changed [.putExercise ⟨1, 4, .chest, false⟩],
  .changed [.putExercise ⟨2, 5, .legs, false⟩],
  .refused .duplicateIdentifier,
  .refused .duplicateExerciseName,
  .refused (.exerciseName .empty),
  .refused (.exerciseName .tooLong),
  .refused (.exerciseName .tooLong),
  .refused (.exerciseName .controlCharacter),
  .changed [.putExercise ⟨3, 7, .abdominals, false⟩],
  .changed [.putExercise ⟨4, 3, .shoulders, false⟩],
  .refused .duplicateExerciseName,
  .changed [],
  .changed [.putExercise ⟨4, 3, .arms, false⟩],
  .changed [.putExercise ⟨4, 6, .abdominals, false⟩],
  .refused .unknownExercise,
  .refused (.exerciseName .empty),
  .changed [.putExercise ⟨2, 5, .legs, true⟩],
  .changed [],
  .changed [.putExercise ⟨2, 5, .legs, false⟩],
  .refused .unknownExercise,
  .changed [.putSet ⟨1, 1, 20766, 6000, 10⟩],
  .refused .duplicateIdentifier,
  .refused .unknownExercise,
  .changed [.putSet ⟨3, 1, (-25567), 99999, 999⟩],
  .changed [.putSet ⟨4, 2, 84370, 1, 1⟩],
  .changed [.putSet ⟨5, 2, (-1), 0, 12⟩],
  .changed [.putSet ⟨1, 1, 20766, 6250, 8⟩],
  .changed [],
  .changed [.putSet ⟨1, 1, 20766, 6250, 9⟩],
  .refused .unknownSet,
  .refused .exerciseHasSets,
  .refused .unknownExercise,
  .refused .unknownSet,
  .changed [.removeSet 1],
  .changed [.removeSet 3],
  .changed [.removeExercise 1],
  .changed [.putExercise ⟨1, 4, .chest, false⟩],
  .changed [.putSet ⟨1, 1, 20766, 6000, 10⟩],
  .changed [.putMemo (-25567) 10],
  .changed [.putMemo 0 3],
  .changed [.putMemo 84370 8],
  .changed [],
  .changed [],
  .changed [.putMemo 20766 11],
  .changed [.removeMemo (-1)],
  .changed [],
  .refused (.memo .controlCharacter),
  .refused (.memo .tooLong)
]

def handWrittenFinal : Log := ⟨
  [⟨7, 0, .back, false⟩, ⟨8, 1, .legs, false⟩, ⟨2, 5, .legs, false⟩, ⟨3, 7, .abdominals, false⟩,
   ⟨4, 6, .abdominals, false⟩, ⟨1, 4, .chest, false⟩],
  [⟨9, 8, 20766, 14000, 5⟩, ⟨2, 7, 20766, 2000, 5⟩, ⟨4, 2, 84370, 1, 1⟩, ⟨5, 2, (-1), 0, 12⟩,
   ⟨1, 1, 20766, 6000, 10⟩],
  [((-25567), 10), (0, 3), (20766, 11), (84370, 8)]⟩

/-- The model gives each step and the last log of the Swift code. -/
theorem outcomes_handWritten :
    outcomes Log.empty handWrittenCommands = (handWrittenSteps, handWrittenFinal) := by
  decide +kernel

/-- A store that receives the changes of each accepted command holds the last log of the Swift code. -/
theorem stored_handWritten :
    stored Log.empty Log.empty handWrittenCommands = handWrittenFinal := by
  decide +kernel

/-- The log of `applied` after the commands is the last log of the Swift code. -/
theorem applied_handWritten :
    applied Log.empty handWrittenCommands = handWrittenFinal := by
  decide +kernel

/-- The model reads the rows of the last log as `TrainingLog.make` does. -/
theorem make_handWrittenFinal :
    make handWrittenFinal = none := by
  decide +kernel

/-- The log keeps the invariants of `Valid`. -/
theorem valid_handWrittenFinal :
    Valid handWrittenFinal := by
  constructor <;> decide +kernel

/-! ## The exercise limit: 9 commands, of which the log accepted 6 and refused 3 -/

set_option maxRecDepth 32768 in
def nearlyFullLog : Log := ⟨
  [⟨1001, 8, .other, false⟩, ⟨1002, 9, .other, false⟩, ⟨1003, 10, .other, false⟩,
   ⟨1004, 11, .other, false⟩, ⟨1005, 12, .other, false⟩, ⟨1006, 13, .other, false⟩,
   ⟨1007, 14, .other, false⟩, ⟨1008, 15, .other, false⟩, ⟨1009, 16, .other, false⟩,
   ⟨1010, 17, .other, false⟩, ⟨1011, 18, .other, false⟩, ⟨1012, 19, .other, false⟩,
   ⟨1013, 20, .other, false⟩, ⟨1014, 21, .other, false⟩, ⟨1015, 22, .other, false⟩,
   ⟨1016, 23, .other, false⟩, ⟨1017, 24, .other, false⟩, ⟨1018, 25, .other, false⟩,
   ⟨1019, 26, .other, false⟩, ⟨1020, 27, .other, false⟩, ⟨1021, 28, .other, false⟩,
   ⟨1022, 29, .other, false⟩, ⟨1023, 30, .other, false⟩, ⟨1024, 31, .other, false⟩,
   ⟨1025, 32, .other, false⟩, ⟨1026, 33, .other, false⟩, ⟨1027, 34, .other, false⟩,
   ⟨1028, 35, .other, false⟩, ⟨1029, 36, .other, false⟩, ⟨1030, 37, .other, false⟩,
   ⟨1031, 38, .other, false⟩, ⟨1032, 39, .other, false⟩, ⟨1033, 40, .other, false⟩,
   ⟨1034, 41, .other, false⟩, ⟨1035, 42, .other, false⟩, ⟨1036, 43, .other, false⟩,
   ⟨1037, 44, .other, false⟩, ⟨1038, 45, .other, false⟩, ⟨1039, 46, .other, false⟩,
   ⟨1040, 47, .other, false⟩, ⟨1041, 48, .other, false⟩, ⟨1042, 49, .other, false⟩,
   ⟨1043, 50, .other, false⟩, ⟨1044, 51, .other, false⟩, ⟨1045, 52, .other, false⟩,
   ⟨1046, 53, .other, false⟩, ⟨1047, 54, .other, false⟩, ⟨1048, 55, .other, false⟩,
   ⟨1049, 56, .other, false⟩, ⟨1050, 57, .other, false⟩, ⟨1051, 58, .other, false⟩,
   ⟨1052, 59, .other, false⟩, ⟨1053, 60, .other, false⟩, ⟨1054, 61, .other, false⟩,
   ⟨1055, 62, .other, false⟩, ⟨1056, 63, .other, false⟩, ⟨1057, 64, .other, false⟩,
   ⟨1058, 65, .other, false⟩, ⟨1059, 66, .other, false⟩, ⟨1060, 67, .other, false⟩,
   ⟨1061, 68, .other, false⟩, ⟨1062, 69, .other, false⟩, ⟨1063, 70, .other, false⟩,
   ⟨1064, 71, .other, false⟩, ⟨1065, 72, .other, false⟩, ⟨1066, 73, .other, false⟩,
   ⟨1067, 74, .other, false⟩, ⟨1068, 75, .other, false⟩, ⟨1069, 76, .other, false⟩,
   ⟨1070, 77, .other, false⟩, ⟨1071, 78, .other, false⟩, ⟨1072, 79, .other, false⟩,
   ⟨1073, 80, .other, false⟩, ⟨1074, 81, .other, false⟩, ⟨1075, 82, .other, false⟩,
   ⟨1076, 83, .other, false⟩, ⟨1077, 84, .other, false⟩, ⟨1078, 85, .other, false⟩,
   ⟨1079, 86, .other, false⟩, ⟨1080, 87, .other, false⟩, ⟨1081, 88, .other, false⟩,
   ⟨1082, 89, .other, false⟩, ⟨1083, 90, .other, false⟩, ⟨1084, 91, .other, false⟩,
   ⟨1085, 92, .other, false⟩, ⟨1086, 93, .other, false⟩, ⟨1087, 94, .other, false⟩,
   ⟨1088, 95, .other, false⟩, ⟨1089, 96, .other, false⟩, ⟨1090, 97, .other, false⟩,
   ⟨1091, 98, .other, false⟩, ⟨1092, 99, .other, false⟩, ⟨1093, 100, .other, false⟩,
   ⟨1094, 101, .other, false⟩, ⟨1095, 102, .other, false⟩, ⟨1096, 103, .other, false⟩,
   ⟨1097, 104, .other, false⟩, ⟨1098, 105, .other, false⟩, ⟨1099, 106, .other, false⟩,
   ⟨1100, 107, .other, false⟩, ⟨1101, 108, .other, false⟩, ⟨1102, 109, .other, false⟩,
   ⟨1103, 110, .other, false⟩, ⟨1104, 111, .other, false⟩, ⟨1105, 112, .other, false⟩,
   ⟨1106, 113, .other, false⟩, ⟨1107, 114, .other, false⟩, ⟨1108, 115, .other, false⟩,
   ⟨1109, 116, .other, false⟩, ⟨1110, 117, .other, false⟩, ⟨1111, 118, .other, false⟩,
   ⟨1112, 119, .other, false⟩, ⟨1113, 120, .other, false⟩, ⟨1114, 121, .other, false⟩,
   ⟨1115, 122, .other, false⟩, ⟨1116, 123, .other, false⟩, ⟨1117, 124, .other, false⟩,
   ⟨1118, 125, .other, false⟩, ⟨1119, 126, .other, false⟩, ⟨1120, 127, .other, false⟩,
   ⟨1121, 128, .other, false⟩, ⟨1122, 129, .other, false⟩, ⟨1123, 130, .other, false⟩,
   ⟨1124, 131, .other, false⟩, ⟨1125, 132, .other, false⟩, ⟨1126, 133, .other, false⟩,
   ⟨1127, 134, .other, false⟩, ⟨1128, 135, .other, false⟩, ⟨1129, 136, .other, false⟩,
   ⟨1130, 137, .other, false⟩, ⟨1131, 138, .other, false⟩, ⟨1132, 139, .other, false⟩,
   ⟨1133, 140, .other, false⟩, ⟨1134, 141, .other, false⟩, ⟨1135, 142, .other, false⟩,
   ⟨1136, 143, .other, false⟩, ⟨1137, 144, .other, false⟩, ⟨1138, 145, .other, false⟩,
   ⟨1139, 146, .other, false⟩, ⟨1140, 147, .other, false⟩, ⟨1141, 148, .other, false⟩,
   ⟨1142, 149, .other, false⟩, ⟨1143, 150, .other, false⟩, ⟨1144, 151, .other, false⟩,
   ⟨1145, 152, .other, false⟩, ⟨1146, 153, .other, false⟩, ⟨1147, 154, .other, false⟩,
   ⟨1148, 155, .other, false⟩, ⟨1149, 156, .other, false⟩, ⟨1150, 157, .other, false⟩,
   ⟨1151, 158, .other, false⟩, ⟨1152, 159, .other, false⟩, ⟨1153, 160, .other, false⟩,
   ⟨1154, 161, .other, false⟩, ⟨1155, 162, .other, false⟩, ⟨1156, 163, .other, false⟩,
   ⟨1157, 164, .other, false⟩, ⟨1158, 165, .other, false⟩, ⟨1159, 166, .other, false⟩,
   ⟨1160, 167, .other, false⟩, ⟨1161, 168, .other, false⟩, ⟨1162, 169, .other, false⟩,
   ⟨1163, 170, .other, false⟩, ⟨1164, 171, .other, false⟩, ⟨1165, 172, .other, false⟩,
   ⟨1166, 173, .other, false⟩, ⟨1167, 174, .other, false⟩, ⟨1168, 175, .other, false⟩,
   ⟨1169, 176, .other, false⟩, ⟨1170, 177, .other, false⟩, ⟨1171, 178, .other, false⟩,
   ⟨1172, 179, .other, false⟩, ⟨1173, 180, .other, false⟩, ⟨1174, 181, .other, false⟩,
   ⟨1175, 182, .other, false⟩, ⟨1176, 183, .other, false⟩, ⟨1177, 184, .other, false⟩,
   ⟨1178, 185, .other, false⟩, ⟨1179, 186, .other, false⟩, ⟨1180, 187, .other, false⟩,
   ⟨1181, 188, .other, false⟩, ⟨1182, 189, .other, false⟩, ⟨1183, 190, .other, false⟩,
   ⟨1184, 191, .other, false⟩, ⟨1185, 192, .other, false⟩, ⟨1186, 193, .other, false⟩,
   ⟨1187, 194, .other, false⟩, ⟨1188, 195, .other, false⟩, ⟨1189, 196, .other, false⟩,
   ⟨1190, 197, .other, false⟩, ⟨1191, 198, .other, false⟩, ⟨1192, 199, .other, false⟩,
   ⟨1193, 200, .other, false⟩, ⟨1194, 201, .other, false⟩, ⟨1195, 202, .other, false⟩,
   ⟨1196, 203, .other, false⟩, ⟨1197, 204, .other, false⟩, ⟨1198, 205, .other, false⟩,
   ⟨1199, 206, .other, false⟩, ⟨1200, 207, .other, false⟩, ⟨1201, 208, .other, false⟩,
   ⟨1202, 209, .other, false⟩, ⟨1203, 210, .other, false⟩, ⟨1204, 211, .other, false⟩,
   ⟨1205, 212, .other, false⟩, ⟨1206, 213, .other, false⟩, ⟨1207, 214, .other, false⟩,
   ⟨1208, 215, .other, false⟩, ⟨1209, 216, .other, false⟩, ⟨1210, 217, .other, false⟩,
   ⟨1211, 218, .other, false⟩, ⟨1212, 219, .other, false⟩, ⟨1213, 220, .other, false⟩,
   ⟨1214, 221, .other, false⟩, ⟨1215, 222, .other, false⟩, ⟨1216, 223, .other, false⟩,
   ⟨1217, 224, .other, false⟩, ⟨1218, 225, .other, false⟩, ⟨1219, 226, .other, false⟩,
   ⟨1220, 227, .other, false⟩, ⟨1221, 228, .other, false⟩, ⟨1222, 229, .other, false⟩,
   ⟨1223, 230, .other, false⟩, ⟨1224, 231, .other, false⟩, ⟨1225, 232, .other, false⟩,
   ⟨1226, 233, .other, false⟩, ⟨1227, 234, .other, false⟩, ⟨1228, 235, .other, false⟩,
   ⟨1229, 236, .other, false⟩, ⟨1230, 237, .other, false⟩, ⟨1231, 238, .other, false⟩,
   ⟨1232, 239, .other, false⟩, ⟨1233, 240, .other, false⟩, ⟨1234, 241, .other, false⟩,
   ⟨1235, 242, .other, false⟩, ⟨1236, 243, .other, false⟩, ⟨1237, 244, .other, false⟩,
   ⟨1238, 245, .other, false⟩, ⟨1239, 246, .other, false⟩, ⟨1240, 247, .other, false⟩,
   ⟨1241, 248, .other, false⟩, ⟨1242, 249, .other, false⟩, ⟨1243, 250, .other, false⟩,
   ⟨1244, 251, .other, false⟩, ⟨1245, 252, .other, false⟩, ⟨1246, 253, .other, false⟩,
   ⟨1247, 254, .other, false⟩, ⟨1248, 255, .other, false⟩, ⟨1249, 256, .other, false⟩,
   ⟨1250, 257, .other, false⟩, ⟨1251, 258, .other, false⟩, ⟨1252, 259, .other, false⟩,
   ⟨1253, 260, .other, false⟩, ⟨1254, 261, .other, false⟩, ⟨1255, 262, .other, false⟩,
   ⟨1256, 263, .other, false⟩, ⟨1257, 264, .other, false⟩, ⟨1258, 265, .other, false⟩,
   ⟨1259, 266, .other, false⟩, ⟨1260, 267, .other, false⟩, ⟨1261, 268, .other, false⟩,
   ⟨1262, 269, .other, false⟩, ⟨1263, 270, .other, false⟩, ⟨1264, 271, .other, false⟩,
   ⟨1265, 272, .other, false⟩, ⟨1266, 273, .other, false⟩, ⟨1267, 274, .other, false⟩,
   ⟨1268, 275, .other, false⟩, ⟨1269, 276, .other, false⟩, ⟨1270, 277, .other, false⟩,
   ⟨1271, 278, .other, false⟩, ⟨1272, 279, .other, false⟩, ⟨1273, 280, .other, false⟩,
   ⟨1274, 281, .other, false⟩, ⟨1275, 282, .other, false⟩, ⟨1276, 283, .other, false⟩,
   ⟨1277, 284, .other, false⟩, ⟨1278, 285, .other, false⟩, ⟨1279, 286, .other, false⟩,
   ⟨1280, 287, .other, false⟩, ⟨1281, 288, .other, false⟩, ⟨1282, 289, .other, false⟩,
   ⟨1283, 290, .other, false⟩, ⟨1284, 291, .other, false⟩, ⟨1285, 292, .other, false⟩,
   ⟨1286, 293, .other, false⟩, ⟨1287, 294, .other, false⟩, ⟨1288, 295, .other, false⟩,
   ⟨1289, 296, .other, false⟩, ⟨1290, 297, .other, false⟩, ⟨1291, 298, .other, false⟩,
   ⟨1292, 299, .other, false⟩, ⟨1293, 300, .other, false⟩, ⟨1294, 301, .other, false⟩,
   ⟨1295, 302, .other, false⟩, ⟨1296, 303, .other, false⟩, ⟨1297, 304, .other, false⟩,
   ⟨1298, 305, .other, false⟩, ⟨1299, 306, .other, false⟩, ⟨1300, 307, .other, false⟩,
   ⟨1301, 308, .other, false⟩, ⟨1302, 309, .other, false⟩, ⟨1303, 310, .other, false⟩,
   ⟨1304, 311, .other, false⟩, ⟨1305, 312, .other, false⟩, ⟨1306, 313, .other, false⟩,
   ⟨1307, 314, .other, false⟩, ⟨1308, 315, .other, false⟩, ⟨1309, 316, .other, false⟩,
   ⟨1310, 317, .other, false⟩, ⟨1311, 318, .other, false⟩, ⟨1312, 319, .other, false⟩,
   ⟨1313, 320, .other, false⟩, ⟨1314, 321, .other, false⟩, ⟨1315, 322, .other, false⟩,
   ⟨1316, 323, .other, false⟩, ⟨1317, 324, .other, false⟩, ⟨1318, 325, .other, false⟩,
   ⟨1319, 326, .other, false⟩, ⟨1320, 327, .other, false⟩, ⟨1321, 328, .other, false⟩,
   ⟨1322, 329, .other, false⟩, ⟨1323, 330, .other, false⟩, ⟨1324, 331, .other, false⟩,
   ⟨1325, 332, .other, false⟩, ⟨1326, 333, .other, false⟩, ⟨1327, 334, .other, false⟩,
   ⟨1328, 335, .other, false⟩, ⟨1329, 336, .other, false⟩, ⟨1330, 337, .other, false⟩,
   ⟨1331, 338, .other, false⟩, ⟨1332, 339, .other, false⟩, ⟨1333, 340, .other, false⟩,
   ⟨1334, 341, .other, false⟩, ⟨1335, 342, .other, false⟩, ⟨1336, 343, .other, false⟩,
   ⟨1337, 344, .other, false⟩, ⟨1338, 345, .other, false⟩, ⟨1339, 346, .other, false⟩,
   ⟨1340, 347, .other, false⟩, ⟨1341, 348, .other, false⟩, ⟨1342, 349, .other, false⟩,
   ⟨1343, 350, .other, false⟩, ⟨1344, 351, .other, false⟩, ⟨1345, 352, .other, false⟩,
   ⟨1346, 353, .other, false⟩, ⟨1347, 354, .other, false⟩, ⟨1348, 355, .other, false⟩,
   ⟨1349, 356, .other, false⟩, ⟨1350, 357, .other, false⟩, ⟨1351, 358, .other, false⟩,
   ⟨1352, 359, .other, false⟩, ⟨1353, 360, .other, false⟩, ⟨1354, 361, .other, false⟩,
   ⟨1355, 362, .other, false⟩, ⟨1356, 363, .other, false⟩, ⟨1357, 364, .other, false⟩,
   ⟨1358, 365, .other, false⟩, ⟨1359, 366, .other, false⟩, ⟨1360, 367, .other, false⟩,
   ⟨1361, 368, .other, false⟩, ⟨1362, 369, .other, false⟩, ⟨1363, 370, .other, false⟩,
   ⟨1364, 371, .other, false⟩, ⟨1365, 372, .other, false⟩, ⟨1366, 373, .other, false⟩,
   ⟨1367, 374, .other, false⟩, ⟨1368, 375, .other, false⟩, ⟨1369, 376, .other, false⟩,
   ⟨1370, 377, .other, false⟩, ⟨1371, 378, .other, false⟩, ⟨1372, 379, .other, false⟩,
   ⟨1373, 380, .other, false⟩, ⟨1374, 381, .other, false⟩, ⟨1375, 382, .other, false⟩,
   ⟨1376, 383, .other, false⟩, ⟨1377, 384, .other, false⟩, ⟨1378, 385, .other, false⟩,
   ⟨1379, 386, .other, false⟩, ⟨1380, 387, .other, false⟩, ⟨1381, 388, .other, false⟩,
   ⟨1382, 389, .other, false⟩, ⟨1383, 390, .other, false⟩, ⟨1384, 391, .other, false⟩,
   ⟨1385, 392, .other, false⟩, ⟨1386, 393, .other, false⟩, ⟨1387, 394, .other, false⟩,
   ⟨1388, 395, .other, false⟩, ⟨1389, 396, .other, false⟩, ⟨1390, 397, .other, false⟩,
   ⟨1391, 398, .other, false⟩, ⟨1392, 399, .other, false⟩, ⟨1393, 400, .other, false⟩,
   ⟨1394, 401, .other, false⟩, ⟨1395, 402, .other, false⟩, ⟨1396, 403, .other, false⟩,
   ⟨1397, 404, .other, false⟩, ⟨1398, 405, .other, false⟩, ⟨1399, 406, .other, false⟩,
   ⟨1400, 407, .other, false⟩, ⟨1401, 408, .other, false⟩, ⟨1402, 409, .other, false⟩,
   ⟨1403, 410, .other, false⟩, ⟨1404, 411, .other, false⟩, ⟨1405, 412, .other, false⟩,
   ⟨1406, 413, .other, false⟩, ⟨1407, 414, .other, false⟩, ⟨1408, 415, .other, false⟩,
   ⟨1409, 416, .other, false⟩, ⟨1410, 417, .other, false⟩, ⟨1411, 418, .other, false⟩,
   ⟨1412, 419, .other, false⟩, ⟨1413, 420, .other, false⟩, ⟨1414, 421, .other, false⟩,
   ⟨1415, 422, .other, false⟩, ⟨1416, 423, .other, false⟩, ⟨1417, 424, .other, false⟩,
   ⟨1418, 425, .other, false⟩, ⟨1419, 426, .other, false⟩, ⟨1420, 427, .other, false⟩,
   ⟨1421, 428, .other, false⟩, ⟨1422, 429, .other, false⟩, ⟨1423, 430, .other, false⟩,
   ⟨1424, 431, .other, false⟩, ⟨1425, 432, .other, false⟩, ⟨1426, 433, .other, false⟩,
   ⟨1427, 434, .other, false⟩, ⟨1428, 435, .other, false⟩, ⟨1429, 436, .other, false⟩,
   ⟨1430, 437, .other, false⟩, ⟨1431, 438, .other, false⟩, ⟨1432, 439, .other, false⟩,
   ⟨1433, 440, .other, false⟩, ⟨1434, 441, .other, false⟩, ⟨1435, 442, .other, false⟩,
   ⟨1436, 443, .other, false⟩, ⟨1437, 444, .other, false⟩, ⟨1438, 445, .other, false⟩,
   ⟨1439, 446, .other, false⟩, ⟨1440, 447, .other, false⟩, ⟨1441, 448, .other, false⟩,
   ⟨1442, 449, .other, false⟩, ⟨1443, 450, .other, false⟩, ⟨1444, 451, .other, false⟩,
   ⟨1445, 452, .other, false⟩, ⟨1446, 453, .other, false⟩, ⟨1447, 454, .other, false⟩,
   ⟨1448, 455, .other, false⟩, ⟨1449, 456, .other, false⟩, ⟨1450, 457, .other, false⟩,
   ⟨1451, 458, .other, false⟩, ⟨1452, 459, .other, false⟩, ⟨1453, 460, .other, false⟩,
   ⟨1454, 461, .other, false⟩, ⟨1455, 462, .other, false⟩, ⟨1456, 463, .other, false⟩,
   ⟨1457, 464, .other, false⟩, ⟨1458, 465, .other, false⟩, ⟨1459, 466, .other, false⟩,
   ⟨1460, 467, .other, false⟩, ⟨1461, 468, .other, false⟩, ⟨1462, 469, .other, false⟩,
   ⟨1463, 470, .other, false⟩, ⟨1464, 471, .other, false⟩, ⟨1465, 472, .other, false⟩,
   ⟨1466, 473, .other, false⟩, ⟨1467, 474, .other, false⟩, ⟨1468, 475, .other, false⟩,
   ⟨1469, 476, .other, false⟩, ⟨1470, 477, .other, false⟩, ⟨1471, 478, .other, false⟩,
   ⟨1472, 479, .other, false⟩, ⟨1473, 480, .other, false⟩, ⟨1474, 481, .other, false⟩,
   ⟨1475, 482, .other, false⟩, ⟨1476, 483, .other, false⟩, ⟨1477, 484, .other, false⟩,
   ⟨1478, 485, .other, false⟩, ⟨1479, 486, .other, false⟩, ⟨1480, 487, .other, false⟩,
   ⟨1481, 488, .other, false⟩, ⟨1482, 489, .other, false⟩, ⟨1483, 490, .other, false⟩,
   ⟨1484, 491, .other, false⟩, ⟨1485, 492, .other, false⟩, ⟨1486, 493, .other, false⟩,
   ⟨1487, 494, .other, false⟩, ⟨1488, 495, .other, false⟩, ⟨1489, 496, .other, false⟩,
   ⟨1490, 497, .other, false⟩, ⟨1491, 498, .other, false⟩, ⟨1492, 499, .other, false⟩,
   ⟨1493, 500, .other, false⟩, ⟨1494, 501, .other, false⟩, ⟨1495, 502, .other, false⟩,
   ⟨1496, 503, .other, false⟩, ⟨1497, 504, .other, false⟩, ⟨1498, 505, .other, false⟩,
   ⟨1499, 506, .other, false⟩, ⟨1500, 507, .other, false⟩, ⟨1501, 508, .other, false⟩,
   ⟨1502, 509, .other, false⟩, ⟨1503, 510, .other, false⟩, ⟨1504, 511, .other, false⟩,
   ⟨1505, 512, .other, false⟩, ⟨1506, 513, .other, false⟩, ⟨1507, 514, .other, false⟩,
   ⟨1508, 515, .other, false⟩, ⟨1509, 516, .other, false⟩, ⟨1510, 517, .other, false⟩,
   ⟨1511, 518, .other, false⟩, ⟨1512, 519, .other, false⟩, ⟨1513, 520, .other, false⟩,
   ⟨1514, 521, .other, false⟩, ⟨1515, 522, .other, false⟩, ⟨1516, 523, .other, false⟩,
   ⟨1517, 524, .other, false⟩, ⟨1518, 525, .other, false⟩, ⟨1519, 526, .other, false⟩,
   ⟨1520, 527, .other, false⟩, ⟨1521, 528, .other, false⟩, ⟨1522, 529, .other, false⟩,
   ⟨1523, 530, .other, false⟩, ⟨1524, 531, .other, false⟩, ⟨1525, 532, .other, false⟩,
   ⟨1526, 533, .other, false⟩, ⟨1527, 534, .other, false⟩, ⟨1528, 535, .other, false⟩,
   ⟨1529, 536, .other, false⟩, ⟨1530, 537, .other, false⟩, ⟨1531, 538, .other, false⟩,
   ⟨1532, 539, .other, false⟩, ⟨1533, 540, .other, false⟩, ⟨1534, 541, .other, false⟩,
   ⟨1535, 542, .other, false⟩, ⟨1536, 543, .other, false⟩, ⟨1537, 544, .other, false⟩,
   ⟨1538, 545, .other, false⟩, ⟨1539, 546, .other, false⟩, ⟨1540, 547, .other, false⟩,
   ⟨1541, 548, .other, false⟩, ⟨1542, 549, .other, false⟩, ⟨1543, 550, .other, false⟩,
   ⟨1544, 551, .other, false⟩, ⟨1545, 552, .other, false⟩, ⟨1546, 553, .other, false⟩,
   ⟨1547, 554, .other, false⟩, ⟨1548, 555, .other, false⟩, ⟨1549, 556, .other, false⟩,
   ⟨1550, 557, .other, false⟩, ⟨1551, 558, .other, false⟩, ⟨1552, 559, .other, false⟩,
   ⟨1553, 560, .other, false⟩, ⟨1554, 561, .other, false⟩, ⟨1555, 562, .other, false⟩,
   ⟨1556, 563, .other, false⟩, ⟨1557, 564, .other, false⟩, ⟨1558, 565, .other, false⟩,
   ⟨1559, 566, .other, false⟩, ⟨1560, 567, .other, false⟩, ⟨1561, 568, .other, false⟩,
   ⟨1562, 569, .other, false⟩, ⟨1563, 570, .other, false⟩, ⟨1564, 571, .other, false⟩,
   ⟨1565, 572, .other, false⟩, ⟨1566, 573, .other, false⟩, ⟨1567, 574, .other, false⟩,
   ⟨1568, 575, .other, false⟩, ⟨1569, 576, .other, false⟩, ⟨1570, 577, .other, false⟩,
   ⟨1571, 578, .other, false⟩, ⟨1572, 579, .other, false⟩, ⟨1573, 580, .other, false⟩,
   ⟨1574, 581, .other, false⟩, ⟨1575, 582, .other, false⟩, ⟨1576, 583, .other, false⟩,
   ⟨1577, 584, .other, false⟩, ⟨1578, 585, .other, false⟩, ⟨1579, 586, .other, false⟩,
   ⟨1580, 587, .other, false⟩, ⟨1581, 588, .other, false⟩, ⟨1582, 589, .other, false⟩,
   ⟨1583, 590, .other, false⟩, ⟨1584, 591, .other, false⟩, ⟨1585, 592, .other, false⟩,
   ⟨1586, 593, .other, false⟩, ⟨1587, 594, .other, false⟩, ⟨1588, 595, .other, false⟩,
   ⟨1589, 596, .other, false⟩, ⟨1590, 597, .other, false⟩, ⟨1591, 598, .other, false⟩,
   ⟨1592, 599, .other, false⟩, ⟨1593, 600, .other, false⟩, ⟨1594, 601, .other, false⟩,
   ⟨1595, 602, .other, false⟩, ⟨1596, 603, .other, false⟩, ⟨1597, 604, .other, false⟩,
   ⟨1598, 605, .other, false⟩, ⟨1599, 606, .other, false⟩, ⟨1600, 607, .other, false⟩,
   ⟨1601, 608, .other, false⟩, ⟨1602, 609, .other, false⟩, ⟨1603, 610, .other, false⟩,
   ⟨1604, 611, .other, false⟩, ⟨1605, 612, .other, false⟩, ⟨1606, 613, .other, false⟩,
   ⟨1607, 614, .other, false⟩, ⟨1608, 615, .other, false⟩, ⟨1609, 616, .other, false⟩,
   ⟨1610, 617, .other, false⟩, ⟨1611, 618, .other, false⟩, ⟨1612, 619, .other, false⟩,
   ⟨1613, 620, .other, false⟩, ⟨1614, 621, .other, false⟩, ⟨1615, 622, .other, false⟩,
   ⟨1616, 623, .other, false⟩, ⟨1617, 624, .other, false⟩, ⟨1618, 625, .other, false⟩,
   ⟨1619, 626, .other, false⟩, ⟨1620, 627, .other, false⟩, ⟨1621, 628, .other, false⟩,
   ⟨1622, 629, .other, false⟩, ⟨1623, 630, .other, false⟩, ⟨1624, 631, .other, false⟩,
   ⟨1625, 632, .other, false⟩, ⟨1626, 633, .other, false⟩, ⟨1627, 634, .other, false⟩,
   ⟨1628, 635, .other, false⟩, ⟨1629, 636, .other, false⟩, ⟨1630, 637, .other, false⟩,
   ⟨1631, 638, .other, false⟩, ⟨1632, 639, .other, false⟩, ⟨1633, 640, .other, false⟩,
   ⟨1634, 641, .other, false⟩, ⟨1635, 642, .other, false⟩, ⟨1636, 643, .other, false⟩,
   ⟨1637, 644, .other, false⟩, ⟨1638, 645, .other, false⟩, ⟨1639, 646, .other, false⟩,
   ⟨1640, 647, .other, false⟩, ⟨1641, 648, .other, false⟩, ⟨1642, 649, .other, false⟩,
   ⟨1643, 650, .other, false⟩, ⟨1644, 651, .other, false⟩, ⟨1645, 652, .other, false⟩,
   ⟨1646, 653, .other, false⟩, ⟨1647, 654, .other, false⟩, ⟨1648, 655, .other, false⟩,
   ⟨1649, 656, .other, false⟩, ⟨1650, 657, .other, false⟩, ⟨1651, 658, .other, false⟩,
   ⟨1652, 659, .other, false⟩, ⟨1653, 660, .other, false⟩, ⟨1654, 661, .other, false⟩,
   ⟨1655, 662, .other, false⟩, ⟨1656, 663, .other, false⟩, ⟨1657, 664, .other, false⟩,
   ⟨1658, 665, .other, false⟩, ⟨1659, 666, .other, false⟩, ⟨1660, 667, .other, false⟩,
   ⟨1661, 668, .other, false⟩, ⟨1662, 669, .other, false⟩, ⟨1663, 670, .other, false⟩,
   ⟨1664, 671, .other, false⟩, ⟨1665, 672, .other, false⟩, ⟨1666, 673, .other, false⟩,
   ⟨1667, 674, .other, false⟩, ⟨1668, 675, .other, false⟩, ⟨1669, 676, .other, false⟩,
   ⟨1670, 677, .other, false⟩, ⟨1671, 678, .other, false⟩, ⟨1672, 679, .other, false⟩,
   ⟨1673, 680, .other, false⟩, ⟨1674, 681, .other, false⟩, ⟨1675, 682, .other, false⟩,
   ⟨1676, 683, .other, false⟩, ⟨1677, 684, .other, false⟩, ⟨1678, 685, .other, false⟩,
   ⟨1679, 686, .other, false⟩, ⟨1680, 687, .other, false⟩, ⟨1681, 688, .other, false⟩,
   ⟨1682, 689, .other, false⟩, ⟨1683, 690, .other, false⟩, ⟨1684, 691, .other, false⟩,
   ⟨1685, 692, .other, false⟩, ⟨1686, 693, .other, false⟩, ⟨1687, 694, .other, false⟩,
   ⟨1688, 695, .other, false⟩, ⟨1689, 696, .other, false⟩, ⟨1690, 697, .other, false⟩,
   ⟨1691, 698, .other, false⟩, ⟨1692, 699, .other, false⟩, ⟨1693, 700, .other, false⟩,
   ⟨1694, 701, .other, false⟩, ⟨1695, 702, .other, false⟩, ⟨1696, 703, .other, false⟩,
   ⟨1697, 704, .other, false⟩, ⟨1698, 705, .other, false⟩, ⟨1699, 706, .other, false⟩,
   ⟨1700, 707, .other, false⟩, ⟨1701, 708, .other, false⟩, ⟨1702, 709, .other, false⟩,
   ⟨1703, 710, .other, false⟩, ⟨1704, 711, .other, false⟩, ⟨1705, 712, .other, false⟩,
   ⟨1706, 713, .other, false⟩, ⟨1707, 714, .other, false⟩, ⟨1708, 715, .other, false⟩,
   ⟨1709, 716, .other, false⟩, ⟨1710, 717, .other, false⟩, ⟨1711, 718, .other, false⟩,
   ⟨1712, 719, .other, false⟩, ⟨1713, 720, .other, false⟩, ⟨1714, 721, .other, false⟩,
   ⟨1715, 722, .other, false⟩, ⟨1716, 723, .other, false⟩, ⟨1717, 724, .other, false⟩,
   ⟨1718, 725, .other, false⟩, ⟨1719, 726, .other, false⟩, ⟨1720, 727, .other, false⟩,
   ⟨1721, 728, .other, false⟩, ⟨1722, 729, .other, false⟩, ⟨1723, 730, .other, false⟩,
   ⟨1724, 731, .other, false⟩, ⟨1725, 732, .other, false⟩, ⟨1726, 733, .other, false⟩,
   ⟨1727, 734, .other, false⟩, ⟨1728, 735, .other, false⟩, ⟨1729, 736, .other, false⟩,
   ⟨1730, 737, .other, false⟩, ⟨1731, 738, .other, false⟩, ⟨1732, 739, .other, false⟩,
   ⟨1733, 740, .other, false⟩, ⟨1734, 741, .other, false⟩, ⟨1735, 742, .other, false⟩,
   ⟨1736, 743, .other, false⟩, ⟨1737, 744, .other, false⟩, ⟨1738, 745, .other, false⟩,
   ⟨1739, 746, .other, false⟩, ⟨1740, 747, .other, false⟩, ⟨1741, 748, .other, false⟩,
   ⟨1742, 749, .other, false⟩, ⟨1743, 750, .other, false⟩, ⟨1744, 751, .other, false⟩,
   ⟨1745, 752, .other, false⟩, ⟨1746, 753, .other, false⟩, ⟨1747, 754, .other, false⟩,
   ⟨1748, 755, .other, false⟩, ⟨1749, 756, .other, false⟩, ⟨1750, 757, .other, false⟩,
   ⟨1751, 758, .other, false⟩, ⟨1752, 759, .other, false⟩, ⟨1753, 760, .other, false⟩,
   ⟨1754, 761, .other, false⟩, ⟨1755, 762, .other, false⟩, ⟨1756, 763, .other, false⟩,
   ⟨1757, 764, .other, false⟩, ⟨1758, 765, .other, false⟩, ⟨1759, 766, .other, false⟩,
   ⟨1760, 767, .other, false⟩, ⟨1761, 768, .other, false⟩, ⟨1762, 769, .other, false⟩,
   ⟨1763, 770, .other, false⟩, ⟨1764, 771, .other, false⟩, ⟨1765, 772, .other, false⟩,
   ⟨1766, 773, .other, false⟩, ⟨1767, 774, .other, false⟩, ⟨1768, 775, .other, false⟩,
   ⟨1769, 776, .other, false⟩, ⟨1770, 777, .other, false⟩, ⟨1771, 778, .other, false⟩,
   ⟨1772, 779, .other, false⟩, ⟨1773, 780, .other, false⟩, ⟨1774, 781, .other, false⟩,
   ⟨1775, 782, .other, false⟩, ⟨1776, 783, .other, false⟩, ⟨1777, 784, .other, false⟩,
   ⟨1778, 785, .other, false⟩, ⟨1779, 786, .other, false⟩, ⟨1780, 787, .other, false⟩,
   ⟨1781, 788, .other, false⟩, ⟨1782, 789, .other, false⟩, ⟨1783, 790, .other, false⟩,
   ⟨1784, 791, .other, false⟩, ⟨1785, 792, .other, false⟩, ⟨1786, 793, .other, false⟩,
   ⟨1787, 794, .other, false⟩, ⟨1788, 795, .other, false⟩, ⟨1789, 796, .other, false⟩,
   ⟨1790, 797, .other, false⟩, ⟨1791, 798, .other, false⟩, ⟨1792, 799, .other, false⟩,
   ⟨1793, 800, .other, false⟩, ⟨1794, 801, .other, false⟩, ⟨1795, 802, .other, false⟩,
   ⟨1796, 803, .other, false⟩, ⟨1797, 804, .other, false⟩, ⟨1798, 805, .other, false⟩,
   ⟨1799, 806, .other, false⟩, ⟨1800, 807, .other, false⟩, ⟨1801, 808, .other, false⟩,
   ⟨1802, 809, .other, false⟩, ⟨1803, 810, .other, false⟩, ⟨1804, 811, .other, false⟩,
   ⟨1805, 812, .other, false⟩, ⟨1806, 813, .other, false⟩, ⟨1807, 814, .other, false⟩,
   ⟨1808, 815, .other, false⟩, ⟨1809, 816, .other, false⟩, ⟨1810, 817, .other, false⟩,
   ⟨1811, 818, .other, false⟩, ⟨1812, 819, .other, false⟩, ⟨1813, 820, .other, false⟩,
   ⟨1814, 821, .other, false⟩, ⟨1815, 822, .other, false⟩, ⟨1816, 823, .other, false⟩,
   ⟨1817, 824, .other, false⟩, ⟨1818, 825, .other, false⟩, ⟨1819, 826, .other, false⟩,
   ⟨1820, 827, .other, false⟩, ⟨1821, 828, .other, false⟩, ⟨1822, 829, .other, false⟩,
   ⟨1823, 830, .other, false⟩, ⟨1824, 831, .other, false⟩, ⟨1825, 832, .other, false⟩,
   ⟨1826, 833, .other, false⟩, ⟨1827, 834, .other, false⟩, ⟨1828, 835, .other, false⟩,
   ⟨1829, 836, .other, false⟩, ⟨1830, 837, .other, false⟩, ⟨1831, 838, .other, false⟩,
   ⟨1832, 839, .other, false⟩, ⟨1833, 840, .other, false⟩, ⟨1834, 841, .other, false⟩,
   ⟨1835, 842, .other, false⟩, ⟨1836, 843, .other, false⟩, ⟨1837, 844, .other, false⟩,
   ⟨1838, 845, .other, false⟩, ⟨1839, 846, .other, false⟩, ⟨1840, 847, .other, false⟩,
   ⟨1841, 848, .other, false⟩, ⟨1842, 849, .other, false⟩, ⟨1843, 850, .other, false⟩,
   ⟨1844, 851, .other, false⟩, ⟨1845, 852, .other, false⟩, ⟨1846, 853, .other, false⟩,
   ⟨1847, 854, .other, false⟩, ⟨1848, 855, .other, false⟩, ⟨1849, 856, .other, false⟩,
   ⟨1850, 857, .other, false⟩, ⟨1851, 858, .other, false⟩, ⟨1852, 859, .other, false⟩,
   ⟨1853, 860, .other, false⟩, ⟨1854, 861, .other, false⟩, ⟨1855, 862, .other, false⟩,
   ⟨1856, 863, .other, false⟩, ⟨1857, 864, .other, false⟩, ⟨1858, 865, .other, false⟩,
   ⟨1859, 866, .other, false⟩, ⟨1860, 867, .other, false⟩, ⟨1861, 868, .other, false⟩,
   ⟨1862, 869, .other, false⟩, ⟨1863, 870, .other, false⟩, ⟨1864, 871, .other, false⟩,
   ⟨1865, 872, .other, false⟩, ⟨1866, 873, .other, false⟩, ⟨1867, 874, .other, false⟩,
   ⟨1868, 875, .other, false⟩, ⟨1869, 876, .other, false⟩, ⟨1870, 877, .other, false⟩,
   ⟨1871, 878, .other, false⟩, ⟨1872, 879, .other, false⟩, ⟨1873, 880, .other, false⟩,
   ⟨1874, 881, .other, false⟩, ⟨1875, 882, .other, false⟩, ⟨1876, 883, .other, false⟩,
   ⟨1877, 884, .other, false⟩, ⟨1878, 885, .other, false⟩, ⟨1879, 886, .other, false⟩,
   ⟨1880, 887, .other, false⟩, ⟨1881, 888, .other, false⟩, ⟨1882, 889, .other, false⟩,
   ⟨1883, 890, .other, false⟩, ⟨1884, 891, .other, false⟩, ⟨1885, 892, .other, false⟩,
   ⟨1886, 893, .other, false⟩, ⟨1887, 894, .other, false⟩, ⟨1888, 895, .other, false⟩,
   ⟨1889, 896, .other, false⟩, ⟨1890, 897, .other, false⟩, ⟨1891, 898, .other, false⟩,
   ⟨1892, 899, .other, false⟩, ⟨1893, 900, .other, false⟩, ⟨1894, 901, .other, false⟩,
   ⟨1895, 902, .other, false⟩, ⟨1896, 903, .other, false⟩, ⟨1897, 904, .other, false⟩,
   ⟨1898, 905, .other, false⟩, ⟨1899, 906, .other, false⟩, ⟨1900, 907, .other, false⟩,
   ⟨1901, 908, .other, false⟩, ⟨1902, 909, .other, false⟩, ⟨1903, 910, .other, false⟩,
   ⟨1904, 911, .other, false⟩, ⟨1905, 912, .other, false⟩, ⟨1906, 913, .other, false⟩,
   ⟨1907, 914, .other, false⟩, ⟨1908, 915, .other, false⟩, ⟨1909, 916, .other, false⟩,
   ⟨1910, 917, .other, false⟩, ⟨1911, 918, .other, false⟩, ⟨1912, 919, .other, false⟩,
   ⟨1913, 920, .other, false⟩, ⟨1914, 921, .other, false⟩, ⟨1915, 922, .other, false⟩,
   ⟨1916, 923, .other, false⟩, ⟨1917, 924, .other, false⟩, ⟨1918, 925, .other, false⟩,
   ⟨1919, 926, .other, false⟩, ⟨1920, 927, .other, false⟩, ⟨1921, 928, .other, false⟩,
   ⟨1922, 929, .other, false⟩, ⟨1923, 930, .other, false⟩, ⟨1924, 931, .other, false⟩,
   ⟨1925, 932, .other, false⟩, ⟨1926, 933, .other, false⟩, ⟨1927, 934, .other, false⟩,
   ⟨1928, 935, .other, false⟩, ⟨1929, 936, .other, false⟩, ⟨1930, 937, .other, false⟩,
   ⟨1931, 938, .other, false⟩, ⟨1932, 939, .other, false⟩, ⟨1933, 940, .other, false⟩,
   ⟨1934, 941, .other, false⟩, ⟨1935, 942, .other, false⟩, ⟨1936, 943, .other, false⟩,
   ⟨1937, 944, .other, false⟩, ⟨1938, 945, .other, false⟩, ⟨1939, 946, .other, false⟩,
   ⟨1940, 947, .other, false⟩, ⟨1941, 948, .other, false⟩, ⟨1942, 949, .other, false⟩,
   ⟨1943, 950, .other, false⟩, ⟨1944, 951, .other, false⟩, ⟨1945, 952, .other, false⟩,
   ⟨1946, 953, .other, false⟩, ⟨1947, 954, .other, false⟩, ⟨1948, 955, .other, false⟩,
   ⟨1949, 956, .other, false⟩, ⟨1950, 957, .other, false⟩, ⟨1951, 958, .other, false⟩,
   ⟨1952, 959, .other, false⟩, ⟨1953, 960, .other, false⟩, ⟨1954, 961, .other, false⟩,
   ⟨1955, 962, .other, false⟩, ⟨1956, 963, .other, false⟩, ⟨1957, 964, .other, false⟩,
   ⟨1958, 965, .other, false⟩, ⟨1959, 966, .other, false⟩, ⟨1960, 967, .other, false⟩,
   ⟨1961, 968, .other, false⟩, ⟨1962, 969, .other, false⟩, ⟨1963, 970, .other, false⟩,
   ⟨1964, 971, .other, false⟩, ⟨1965, 972, .other, false⟩, ⟨1966, 973, .other, false⟩,
   ⟨1967, 974, .other, false⟩, ⟨1968, 975, .other, false⟩, ⟨1969, 976, .other, false⟩,
   ⟨1970, 977, .other, false⟩, ⟨1971, 978, .other, false⟩, ⟨1972, 979, .other, false⟩,
   ⟨1973, 980, .other, false⟩, ⟨1974, 981, .other, false⟩, ⟨1975, 982, .other, false⟩,
   ⟨1976, 983, .other, false⟩, ⟨1977, 984, .other, false⟩, ⟨1978, 985, .other, false⟩,
   ⟨1979, 986, .other, false⟩, ⟨1980, 987, .other, false⟩, ⟨1981, 988, .other, false⟩,
   ⟨1982, 989, .other, false⟩, ⟨1983, 990, .other, false⟩, ⟨1984, 991, .other, false⟩,
   ⟨1985, 992, .other, false⟩, ⟨1986, 993, .other, false⟩, ⟨1987, 994, .other, false⟩,
   ⟨1988, 995, .other, false⟩, ⟨1989, 996, .other, false⟩, ⟨1990, 997, .other, false⟩,
   ⟨1991, 998, .other, false⟩, ⟨1992, 999, .other, false⟩, ⟨1993, 1000, .other, false⟩,
   ⟨1994, 1001, .other, false⟩, ⟨1995, 1002, .other, false⟩, ⟨1996, 1003, .other, false⟩,
   ⟨1997, 1004, .other, false⟩, ⟨1998, 1005, .other, false⟩, ⟨1999, 1006, .other, false⟩],
  [],
  []⟩

def exerciseLimitCommands : List Command := [
  .replaceAll nearlyFullLog,
  .addExercise 2000 (.accepted 1007) .chest,
  .addExercise 1001 (.accepted 1008) .chest,
  .addExercise 2001 (.accepted 8) .chest,
  .addExercise 2001 (.accepted 1008) .chest,
  .deleteExercise 2000,
  .addExercise 2001 (.accepted 1008) .chest,
  .replaceAll ⟨[], [], []⟩,
  .addExercise 1 (.accepted 4) .chest
]

def exerciseLimitSteps : List Step := [
  .changed [.replaceAll nearlyFullLog],
  .changed [.putExercise ⟨2000, 1007, .chest, false⟩],
  .refused .duplicateIdentifier,
  .refused .duplicateExerciseName,
  .refused .full,
  .changed [.removeExercise 2000],
  .changed [.putExercise ⟨2001, 1008, .chest, false⟩],
  .changed [.replaceAll ⟨[], [], []⟩],
  .changed [.putExercise ⟨1, 4, .chest, false⟩]
]

def exerciseLimitFinal : Log := ⟨
  [⟨1, 4, .chest, false⟩],
  [],
  []⟩

/-- The model gives each step and the last log of the Swift code. -/
theorem outcomes_exerciseLimit :
    outcomes Log.empty exerciseLimitCommands = (exerciseLimitSteps, exerciseLimitFinal) := by
  decide +kernel

/-- A store that receives the changes of each accepted command holds the last log of the Swift code. -/
theorem stored_exerciseLimit :
    stored Log.empty Log.empty exerciseLimitCommands = exerciseLimitFinal := by
  decide +kernel

/-- The log of `applied` after the commands is the last log of the Swift code. -/
theorem applied_exerciseLimit :
    applied Log.empty exerciseLimitCommands = exerciseLimitFinal := by
  decide +kernel

/-- The model reads the rows of the last log as `TrainingLog.make` does. -/
theorem make_exerciseLimitFinal :
    make exerciseLimitFinal = none := by
  decide +kernel

/-- The log keeps the invariants of `Valid`. -/
theorem valid_exerciseLimitFinal :
    Valid exerciseLimitFinal := by
  constructor <;> decide +kernel

/-! ## The set limit: 5 commands, of which the log accepted 2 and refused 3 -/

set_option maxRecDepth 32768 in
def nearlyFullOfSets : Log := ⟨
  [⟨1, 4, .chest, false⟩],
  (List.range 999999).map (fun (i : Nat) => ⟨i + 1, 1, 20766, 6000, 1⟩),
  []⟩

set_option maxRecDepth 32768 in
def fullOfSets : Log := ⟨
  [⟨1, 4, .chest, false⟩],
  (List.range 1000000).map (fun (i : Nat) => ⟨i + 1, 1, 20766, 6000, 1⟩),
  []⟩

/-- The log keeps the invariants of `Valid`. -/
theorem valid_nearlyFullOfSets : Valid nearlyFullOfSets where
  exerciseIDs := by decide +kernel
  exerciseNames := by decide +kernel
  setIDs := by
    simp only [nearlyFullOfSets, List.map_map]
    exact List.Pairwise.map _
      (fun (a b : Nat) (different : a ≠ b) => show a + 1 ≠ b + 1 by omega)
      List.nodup_range
  setsNameExercises := by
    intro set member
    simp only [nearlyFullOfSets, List.mem_map, List.mem_range] at member
    obtain ⟨i, _, made⟩ := member
    subst made
    exact ⟨⟨1, 4, .chest, false⟩, by decide +kernel, rfl⟩
  exerciseCount := by decide +kernel
  setCount := by
    simp only [nearlyFullOfSets, List.length_map, List.length_range]
    decide
  memoDays := by decide +kernel

/-- The log keeps the invariants of `Valid`. -/
theorem valid_fullOfSets : Valid fullOfSets where
  exerciseIDs := by decide +kernel
  exerciseNames := by decide +kernel
  setIDs := by
    simp only [fullOfSets, List.map_map]
    exact List.Pairwise.map _
      (fun (a b : Nat) (different : a ≠ b) => show a + 1 ≠ b + 1 by omega)
      List.nodup_range
  setsNameExercises := by
    intro set member
    simp only [fullOfSets, List.mem_map, List.mem_range] at member
    obtain ⟨i, _, made⟩ := member
    subst made
    exact ⟨⟨1, 4, .chest, false⟩, by decide +kernel, rfl⟩
  exerciseCount := by decide +kernel
  setCount := by
    simp only [fullOfSets, List.length_map, List.length_range]
    decide
  memoDays := by decide +kernel

/-- The model gives the result of the Swift code for command 0, counted from zero. -/
theorem apply_setLimit_0 :
    apply ⟨[], [], []⟩ (.replaceAll nearlyFullOfSets) =
      .accepted ⟨nearlyFullOfSets, [.replaceAll nearlyFullOfSets]⟩ := by
  rfl

/-- The model gives the result of the Swift code for command 1, counted from zero. -/
theorem apply_setLimit_1 :
    apply nearlyFullOfSets (.logSet 1000000 1 20766 6000 1) =
      .accepted ⟨fullOfSets, [.putSet ⟨1000000, 1, 20766, 6000, 1⟩]⟩ := by
  have exercise : (nearlyFullOfSets.exercise? 1).isNone = false := by decide +kernel
  have set : nearlyFullOfSets.set? 1000000 = none := by
    simp only [Log.set?, nearlyFullOfSets, List.find?_eq_none, List.mem_map, List.mem_range]
    intro set ⟨i, bound, made⟩
    subst made
    simp only [beq_iff_eq]
    show ¬(i + 1 = 1000000)
    omega
  have count : nearlyFullOfSets.sets.length = 999999 := by
    simp only [nearlyFullOfSets, List.length_map, List.length_range]
  have grown :
      fullOfSets =
        { nearlyFullOfSets with sets := nearlyFullOfSets.sets ++ [⟨1000000, 1, 20766, 6000, 1⟩] } := by
    simp only [nearlyFullOfSets, fullOfSets, List.range_succ (n := 999999), List.map_append, List.map_cons, List.map_nil]
  simp only [apply, logSet, exercise, set, count, grown]
  all_goals rfl

/-- The model gives the result of the Swift code for command 2, counted from zero. -/
theorem apply_setLimit_2 :
    apply fullOfSets (.logSet 1000001 1 20766 6000 1) =
      .refused .full := by
  have exercise : (fullOfSets.exercise? 1).isNone = false := by decide +kernel
  have set : fullOfSets.set? 1000001 = none := by
    simp only [Log.set?, fullOfSets, List.find?_eq_none, List.mem_map, List.mem_range]
    intro set ⟨i, bound, made⟩
    subst made
    simp only [beq_iff_eq]
    show ¬(i + 1 = 1000001)
    omega
  have count : fullOfSets.sets.length = 1000000 := by
    simp only [fullOfSets, List.length_map, List.length_range]
  simp only [apply, logSet, exercise, set, count]
  all_goals decide

/-- The model gives the result of the Swift code for command 3, counted from zero. -/
theorem apply_setLimit_3 :
    apply fullOfSets (.logSet 1000001 9 20766 6000 1) =
      .refused .unknownExercise := by
  have exercise : (fullOfSets.exercise? 9).isNone = true := by decide +kernel
  have set : fullOfSets.set? 1000001 = none := by
    simp only [Log.set?, fullOfSets, List.find?_eq_none, List.mem_map, List.mem_range]
    intro set ⟨i, bound, made⟩
    subst made
    simp only [beq_iff_eq]
    show ¬(i + 1 = 1000001)
    omega
  have count : fullOfSets.sets.length = 1000000 := by
    simp only [fullOfSets, List.length_map, List.length_range]
  simp only [apply, logSet, exercise, set, count]
  all_goals decide

/-- The model gives the result of the Swift code for command 4, counted from zero. -/
theorem apply_setLimit_4 :
    apply fullOfSets (.logSet 1 1 20766 6000 1) =
      .refused .duplicateIdentifier := by
  have exercise : (fullOfSets.exercise? 1).isNone = false := by decide +kernel
  have set : (fullOfSets.set? 1).isSome = true := by
    simp only [Log.set?, fullOfSets, List.find?_isSome, List.mem_map, List.mem_range]
    exact ⟨_, ⟨0, by decide, rfl⟩, by decide⟩
  have count : fullOfSets.sets.length = 1000000 := by
    simp only [fullOfSets, List.length_map, List.length_range]
  simp only [apply, logSet, exercise, set, count]
  all_goals decide

/-! ## Rows that `TrainingLog.make` reads -/

/-- Rows that keep every invariant form a log. -/
theorem make_wholeRows :
    make ⟨[⟨1, 4, .chest, false⟩, ⟨2, 5, .legs, true⟩], [⟨1, 1, 20766, 6000, 10⟩, ⟨2, 2, (-1), 6000, 10⟩], [(20766, 8)]⟩ =
      none := by
  decide +kernel

/-- The rows keep the invariants of `Valid`. -/
theorem valid_wholeRows :
    Valid ⟨[⟨1, 4, .chest, false⟩, ⟨2, 5, .legs, true⟩], [⟨1, 1, 20766, 6000, 10⟩, ⟨2, 2, (-1), 6000, 10⟩], [(20766, 8)]⟩ := by
  constructor <;> decide +kernel

/-- Two exercises bear one identifier. -/
theorem make_repeatedExerciseIdentifier :
    make ⟨[⟨1, 4, .chest, false⟩, ⟨2, 5, .legs, true⟩, ⟨1, 1, .back, false⟩], [], []⟩ =
      some .duplicateExerciseID := by
  decide +kernel

/-- The rows break `exerciseIDs` of `Valid`. -/
theorem invalid_repeatedExerciseIdentifier :
    ¬Valid ⟨[⟨1, 4, .chest, false⟩, ⟨2, 5, .legs, true⟩, ⟨1, 1, .back, false⟩], [], []⟩ := by
  intro valid
  exact absurd valid.exerciseIDs (by decide +kernel)

/-- Two exercises bear one name. -/
theorem make_repeatedExerciseName :
    make ⟨[⟨1, 4, .chest, false⟩, ⟨2, 5, .legs, true⟩, ⟨3, 4, .other, false⟩], [], []⟩ =
      some .duplicateExerciseName := by
  decide +kernel

/-- The rows break `exerciseNames` of `Valid`. -/
theorem invalid_repeatedExerciseName :
    ¬Valid ⟨[⟨1, 4, .chest, false⟩, ⟨2, 5, .legs, true⟩, ⟨3, 4, .other, false⟩], [], []⟩ := by
  intro valid
  exact absurd valid.exerciseNames (by decide +kernel)

/-- An exercise that repeats an identifier and a name is refused for its identifier. -/
theorem make_repeatedExercise :
    make ⟨[⟨1, 4, .chest, false⟩, ⟨1, 4, .chest, false⟩], [], []⟩ =
      some .duplicateExerciseID := by
  decide +kernel

/-- The rows break `exerciseIDs` of `Valid`. -/
theorem invalid_repeatedExercise :
    ¬Valid ⟨[⟨1, 4, .chest, false⟩, ⟨1, 4, .chest, false⟩], [], []⟩ := by
  intro valid
  exact absurd valid.exerciseIDs (by decide +kernel)

/-- Two sets bear one identifier. -/
theorem make_repeatedSetIdentifier :
    make ⟨[⟨1, 4, .chest, false⟩, ⟨2, 5, .legs, true⟩], [⟨1, 1, 20766, 6000, 10⟩, ⟨2, 2, (-1), 6000, 10⟩, ⟨1, 2, 20766, 6000, 10⟩], []⟩ =
      some .duplicateSetID := by
  decide +kernel

/-- The rows break `setIDs` of `Valid`. -/
theorem invalid_repeatedSetIdentifier :
    ¬Valid ⟨[⟨1, 4, .chest, false⟩, ⟨2, 5, .legs, true⟩], [⟨1, 1, 20766, 6000, 10⟩, ⟨2, 2, (-1), 6000, 10⟩, ⟨1, 2, 20766, 6000, 10⟩], []⟩ := by
  intro valid
  exact absurd valid.setIDs (by decide +kernel)

/-- A set names an exercise that the rows don't hold. -/
theorem make_setOfNoExercise :
    make ⟨[⟨1, 4, .chest, false⟩], [⟨1, 1, 20766, 6000, 10⟩, ⟨2, 2, (-1), 6000, 10⟩], []⟩ =
      some .unknownExercise := by
  decide +kernel

/-- The rows break `setsNameExercises` of `Valid`. -/
theorem invalid_setOfNoExercise :
    ¬Valid ⟨[⟨1, 4, .chest, false⟩], [⟨1, 1, 20766, 6000, 10⟩, ⟨2, 2, (-1), 6000, 10⟩], []⟩ := by
  intro valid
  exact absurd valid.setsNameExercises (by decide +kernel)

/-- A set that repeats an identifier and names no exercise is refused for its identifier. -/
theorem make_repeatedSetOfNoExercise :
    make ⟨[⟨1, 4, .chest, false⟩], [⟨1, 1, 20766, 6000, 10⟩, ⟨1, 9, 20766, 6000, 10⟩], []⟩ =
      some .duplicateSetID := by
  decide +kernel

/-- The rows break `setIDs` of `Valid`. -/
theorem invalid_repeatedSetOfNoExercise :
    ¬Valid ⟨[⟨1, 4, .chest, false⟩], [⟨1, 1, 20766, 6000, 10⟩, ⟨1, 9, 20766, 6000, 10⟩], []⟩ := by
  intro valid
  exact absurd valid.setIDs (by decide +kernel)

/-- The first set that breaks the rows decides the refusal. -/
theorem make_strayThenRepeatedSet :
    make ⟨[⟨1, 4, .chest, false⟩], [⟨1, 9, 20766, 6000, 10⟩, ⟨1, 1, 20766, 6000, 10⟩], []⟩ =
      some .unknownExercise := by
  decide +kernel

/-- The rows break `setsNameExercises` of `Valid`. -/
theorem invalid_strayThenRepeatedSet :
    ¬Valid ⟨[⟨1, 4, .chest, false⟩], [⟨1, 9, 20766, 6000, 10⟩, ⟨1, 1, 20766, 6000, 10⟩], []⟩ := by
  intro valid
  exact absurd valid.setsNameExercises (by decide +kernel)

/-- The exercises are read before the sets. -/
theorem make_brokenExercisesAndSets :
    make ⟨[⟨1, 4, .chest, false⟩, ⟨3, 4, .other, false⟩], [⟨1, 9, 20766, 6000, 10⟩], []⟩ =
      some .duplicateExerciseName := by
  decide +kernel

/-- The rows break `exerciseNames` of `Valid`. -/
theorem invalid_brokenExercisesAndSets :
    ¬Valid ⟨[⟨1, 4, .chest, false⟩, ⟨3, 4, .other, false⟩], [⟨1, 9, 20766, 6000, 10⟩], []⟩ := by
  intro valid
  exact absurd valid.exerciseNames (by decide +kernel)

/-- A thousand exercises pass the limit, so their first repeated row decides. -/
theorem make_exercisesAtTheLimit :
    make ⟨List.replicate 1000 ⟨1, 4, .chest, false⟩, [], []⟩ =
      some .duplicateExerciseID := by
  decide +kernel

/-- The rows break `exerciseIDs` of `Valid`. -/
theorem invalid_exercisesAtTheLimit :
    ¬Valid ⟨List.replicate 1000 ⟨1, 4, .chest, false⟩, [], []⟩ := by
  intro valid
  exact absurd valid.exerciseIDs (by decide +kernel)

/-- One exercise more than a thousand is refused before any row is read. -/
theorem make_exercisesBeyondTheLimit :
    make ⟨List.replicate 1001 ⟨1, 4, .chest, false⟩, [], []⟩ =
      some .tooManyExercises := by
  decide +kernel

/-- The rows break `exerciseCount` of `Valid`. -/
theorem invalid_exercisesBeyondTheLimit :
    ¬Valid ⟨List.replicate 1001 ⟨1, 4, .chest, false⟩, [], []⟩ := by
  intro valid
  exact absurd valid.exerciseCount (by decide +kernel)

/-- A million sets pass the limit, so their first set, which names no exercise, decides. -/
theorem make_setsAtTheLimit :
    make ⟨[], List.replicate 1000000 ⟨1, 1, 20766, 6000, 10⟩, []⟩ =
      some .unknownExercise := by
  simp only [make, List.length_replicate, List.length_nil]
  decide

/-- The rows break `setsNameExercises` of `Valid`. -/
theorem invalid_setsAtTheLimit :
    ¬Valid ⟨[], List.replicate 1000000 ⟨1, 1, 20766, 6000, 10⟩, []⟩ := by
  intro valid
  obtain ⟨_, member, _⟩ := valid.setsNameExercises _ (List.mem_replicate.2 ⟨by decide, rfl⟩)
  nomatch member

/-- One set more than a million is refused before any row is read. -/
theorem make_setsBeyondTheLimit :
    make ⟨[], List.replicate 1000001 ⟨1, 1, 20766, 6000, 10⟩, []⟩ =
      some .tooManySets := by
  simp only [make, List.length_replicate, List.length_nil]
  decide

/-- The rows break `setCount` of `Valid`. -/
theorem invalid_setsBeyondTheLimit :
    ¬Valid ⟨[], List.replicate 1000001 ⟨1, 1, 20766, 6000, 10⟩, []⟩ := by
  intro valid
  exact absurd valid.setCount (by simp only [List.length_replicate]; decide)

/-- Rows beyond both limits are refused for their exercises. -/
theorem make_beyondBothLimits :
    make ⟨List.replicate 1001 ⟨1, 4, .chest, false⟩, List.replicate 1000001 ⟨1, 1, 20766, 6000, 10⟩, []⟩ =
      some .tooManyExercises := by
  simp only [make, List.length_replicate]
  decide

/-- The rows break `exerciseCount` of `Valid`. -/
theorem invalid_beyondBothLimits :
    ¬Valid ⟨List.replicate 1001 ⟨1, 4, .chest, false⟩, List.replicate 1000001 ⟨1, 1, 20766, 6000, 10⟩, []⟩ := by
  intro valid
  exact absurd valid.exerciseCount (by decide +kernel)

end Gymemo.Log.Vectors
