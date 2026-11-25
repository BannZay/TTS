;; Renders each diphone request from pairs.scm with the kal_diphone voice (real recorded diphone database, residual LPC),
;; at three phone lengths (variants 1..3) so the addon can pick the length that fits the rhythm it wants.
;; Phones utterances use fixed duration (FP_duration, milliseconds per phone) and monotone pitch (FP_F0).
;; Output: <workdir>/wav/<key><variant>.wav and one line per file on stdout:
;;   "key<variant> E <segment ends> S <segment source ends> U <unit ends (source time)>"  (seconds)
(voice_kal_diphone)
(set! FP_F0 110)
(load "@ROOT@/tools/festival/work/pairs.scm")
(set! vc_variants '(("1" 66) ("2" 105) ("3" 160)))
(mapcar
 (lambda (v)
   (set! FP_duration (car (cdr v)))
   (mapcar
    (lambda (p)
      (let ((utt (eval (list 'Utterance 'Phones (car (cdr p)))))
            (name (string-append (car p) (car v))))
        (utt.synth utt)
        (utt.save.wave utt (string-append "@ROOT@/tools/festival/work/wav/" name ".wav") 'riff)
        (format t "%s E %l S %l U %l\n" name
                (mapcar (lambda (s) (item.feat s "end")) (utt.relation.items utt 'Segment))
                (mapcar (lambda (s) (item.feat s "source_end")) (utt.relation.items utt 'Segment))
                (mapcar (lambda (u) (item.feat u "end")) (utt.relation.items utt 'Unit)))))
    vc_pairs))
 vc_variants)
