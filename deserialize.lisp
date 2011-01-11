(in-package #:vivace-graph-v2)

(defgeneric deserialize (code stream))
(defgeneric deserialize-action (code stream))

(defun deserialize-file (file)
  (with-open-file (stream file :element-type '(unsigned-byte 8))
    (do ((code (read-byte stream nil :eof) (read-byte stream nil :eof)))
	((eql code :eof))
      (format t "CODE ~A: ~A~%" code (deserialize code stream)))))

(defmethod deserialize :around (code stream)
  (handler-case
      (call-next-method)
    (error (condition)
      (error 'deserialization-error :instance stream :reason condition))))

(defun deserialize-integer (stream)
  (let ((int 0) (n-bytes (read-byte stream)))
    (dotimes (i n-bytes)
      (setq int (dpb (read-byte stream) (byte 8 (* i 8)) int)))
    int))

(defmethod deserialize ((code (eql +negative-integer+)) stream)
  (- (deserialize-integer stream)))

(defmethod deserialize ((code (eql +positive-integer+)) stream)
  (deserialize-integer stream))

(defmethod deserialize ((code (eql +ratio+)) stream)
  (let ((numerator (deserialize (read-byte stream) stream))
	(denominator (deserialize (read-byte stream) stream)))
    (/ numerator denominator)))

(defmethod deserialize ((code (eql +single-float+)) stream)
  (ieee-floats:decode-float32 (deserialize-integer stream)))

(defmethod deserialize ((code (eql +double-float+)) stream)
  (ieee-floats:decode-float64 (deserialize-integer stream)))

(defmethod deserialize ((code (eql +character+)) stream)
  (let ((char-code (deserialize-integer stream)))
    (code-char char-code)))

(defmethod deserialize ((code (eql +string+)) stream)
  (let* ((length (deserialize (read-byte stream) stream))
	 (array (make-array length :element-type '(unsigned-byte 8))))
    (dotimes (i length)
      (setf (aref array i) (read-byte stream)))
    (sb-ext:octets-to-string array)))

(defmethod deserialize ((code (eql +symbol+)) stream)
  (let ((code (read-byte stream)))
    (when (/= +string+ code)
      (error 'deserialization-error :instance code :reason 
	     "Symbol-name is not a string!"))
    (let ((symbol-name (deserialize code stream)))
      (setq code (read-byte stream))
      (when (/= +string+ code)
	(error 'deserialization-error :instance code :reason 
	       "Symbol-package is not a string!"))
      (let* ((pkg-name (deserialize code stream))
	     (pkg (find-package pkg-name)))
	(when (null pkg)
	  (error 'deserialization-error :instance code :reason 
		 (format nil "Symbol-package ~A does not exist!" pkg-name)))
	(intern symbol-name pkg)))))

(defun deserialize-sequence (stream type)
  (let* ((length (deserialize (read-byte stream) stream))
	 (seq (make-sequence type length)))
    (dotimes (i length)
      (setf (elt seq i) (deserialize (read-byte stream) stream)))
    seq))

(defmethod deserialize ((code (eql +list+)) stream)
  (deserialize-sequence stream 'list))

(defmethod deserialize ((code (eql +vector+)) stream)
  (deserialize-sequence stream 'vector))

(defmethod deserialize ((code (eql +uuid+)) stream)
  (let ((array (make-array 16 :element-type '(unsigned-byte 8))))
    (dotimes (i 16)
      (let ((byte (read-byte stream)))
	(cond ((= i 4)  (setf (aref array 5) byte))
	      ((= i 5)  (setf (aref array 4) byte))
	      ((= i 6)  (setf (aref array 7) byte))
	      ((= i 7)  (setf (aref array 6) byte))
	      ((= i 10) (setf (aref array 15) byte))
	      ((= i 11) (setf (aref array 14) byte))
	      ((= i 12) (setf (aref array 13) byte))
	      ((= i 13) (setf (aref array 12) byte))
	      ((= i 14) (setf (aref array 11) byte))
	      ((= i 15) (setf (aref array 10) byte))
	      (t        (setf (aref array i) byte)))))
    (uuid:byte-array-to-uuid array)))
