(in-package #:vivace-graph-v2)

(defgeneric serialize (thing stream))
(defgeneric serialize-action (action stream &rest args))

(defmethod serialize :around (thing stream)
  (handler-case
      (call-next-method)
    (error (condition)
      (error 'serialization-error :instance thing :reason condition))))

(defun serialize-integer (int stream)
  (let ((n-bytes (ceiling (integer-length int) 8)))
    (write-byte n-bytes stream)
    (dotimes (i n-bytes)
      (write-byte (ldb (byte 8 0) int) stream)
      (setq int (ash int -8)))))

(defmethod serialize ((int integer) (stream stream))
  "Encodes integers between (- (1- (expt 2 (* 8 255)))) and (1- (expt 2 (* 8 255)))"
  (if (minusp int)
      (progn
	(write-byte +negative-integer+ stream)
	(setq int (abs int)))
      (write-byte +positive-integer+ stream))
  (serialize-integer int stream))

(defmethod serialize ((ratio ratio) (stream stream))
  (let* ((numerator (numerator ratio)) (denominator (denominator ratio)))
    (write-byte +ratio+ stream)
    (serialize numerator stream)
    (serialize denominator stream)))

(defmethod serialize ((float single-float) (stream stream))
  (write-byte +single-float+ stream)
  (serialize-integer (ieee-floats:encode-float32 float) stream))

(defmethod serialize ((float double-float) (stream stream))
  (write-byte +single-float+ stream)
  (serialize-integer (ieee-floats:encode-float64 float) stream))

(defmethod serialize ((char character) (stream stream))
  (write-byte +character+ stream)
  (serialize-integer (char-code char) stream))

(defmethod serialize ((string string) (stream stream))
  (let* ((unicode (sb-ext:string-to-octets string))
	 (length (length unicode)))
    (write-byte +string+ stream)
    (serialize length stream)
    (dotimes (i length)
      (write-byte (aref unicode i) stream))))

(defmethod serialize ((symbol symbol) (stream stream))
  (cond ((null symbol)
	 (write-byte +null+ stream))
        ((eq symbol t)
	 (write-byte +t+ stream))
        (t
	 (write-byte +symbol+ stream)
	 (serialize (symbol-name symbol) stream)
	 (serialize (package-name (symbol-package symbol)) stream))))

(defmethod serialize ((uuid uuid:uuid) (stream stream))
  (write-byte +uuid+ stream)
  (uuid:serialize-uuid uuid stream))

(defun serialize-sequence (seq stream code)
  (let ((length (length seq)))
    (write-byte code stream)
    (serialize length stream)
    (dotimes (i length)
      (serialize (elt seq i) stream))))

(defmethod serialize ((list list) (stream stream))
  (serialize-sequence list stream +list+))

(defmethod serialize ((vector vector) (stream stream))
  (serialize-sequence vector stream +vector+))

(defmethod serialize ((triple triple) (stream stream))
  (write-byte +triple+ stream)
  (serialize (subject triple) stream)
  (serialize (predicate triple) stream)
  (serialize (object triple) stream)
  (serialize (graph triple) stream)
  (serialize (id triple) stream)
  (serialize (deleted? triple) stream)
  (serialize (cf triple) stream))

(defmethod serialize-action ((action (eql :add-triple)) stream &rest args)
  (write-byte +add-triple+ stream)
  (serialize (nth 0 args) stream)  ;; subject
  (serialize (nth 1 args) stream)  ;; predicate
  (serialize (nth 2 args) stream)  ;; object
  (serialize (nth 3 args) stream)  ;; graph
  (serialize (nth 4 args) stream)  ;; id
  (serialize (nth 5 args) stream)  ;; deleted?
  (serialize (nth 6 args) stream)) ;; cf

(defmethod serialize-action ((action (eql :delete-triple)) stream &rest args)
  (write-byte +delete-triple+ stream)
  (serialize (nth 0 args) stream)  ;; id
  (serialize (nth 1 args) stream)) ;; timestamp

(defmethod serialize-action ((action (eql :undelete-triple)) stream &rest args)
  (write-byte +delete-triple+ stream)
  (serialize (nth 0 args) stream)) ;; id

(defmethod serialize-action ((action (eql :set-cf)) stream &rest args)
  (write-byte +delete-triple+ stream)
  (serialize (nth 0 args) stream)  ;; id
  (serialize (nth 1 args) stream)) ;; cf

(defmethod serialize-action ((action (eql :transaction)) stream &rest args)
  (write-byte +transaction+ stream)
  (let ((tx (nth 0 args)))
    (serialize (length tx) stream)
    (dolist (action tx)
      (apply #'serialize-action 
	     (nconc (list (first action) stream) (rest action))))))

(defun test-serializer (file)
  (with-open-file (stream file
			  :direction :output
			  :element-type '(unsigned-byte 8)
			  :if-exists :overwrite
			  :if-does-not-exist :create)
    (let ((uuid (make-uuid))
	  (vec (make-array 5)))
      (setf (aref vec 0) 1)
      (setf (aref vec 1) #\a)
      (setf (aref vec 2) "string")
      (setf (aref vec 3) 'symbol)
      (setf (aref vec 4) uuid)
      (format t "UUID IS ~A~%" uuid)
      (serialize 123 stream)
      (serialize 123.123 stream)
      (serialize 123/555 stream)
      (serialize #\a stream)
      (serialize "string" stream)
      (serialize 'symbol stream)
      (serialize uuid stream)
      (serialize (list 1 #\a "string" 'symbol uuid) stream)
      (serialize vec stream)))
  (deserialize-file file))