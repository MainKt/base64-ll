target triple = "x86_64-unknown-freebsd15.0"

@.write.error = constant [16 x i8] c"Unable to write\00"
@.read.error = constant [15 x i8] c"Unable to read\00"

@.base64.chars = constant [64 x i8] c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

define i8 @base64.char(i6 %index) {
  %index.i8 = zext i6 %index to i8
  %char = getelementptr i8, ptr @.base64.chars, i8 %index.i8
  %char.val = load i8, ptr %char
  ret i8 %char.val
}

define i64 @encode(ptr %buf, i64 %size, ptr %out) {
entry:
  %chunk.i8.reversed = load <3 x i8>, ptr %buf
  %chunk.i8 = call <3 x i8> @llvm.vector.reverse.v3i8 (<3 x i8> %chunk.i8.reversed)
  %chunk.reversed = bitcast <3 x i8> %chunk.i8 to <4 x i6>
  %chunk = call <4 x i6> @llvm.vector.reverse.v4i6 (<4 x i6> %chunk.reversed)

  %octets = mul i64 %size, 8
  %octets.plus5 = add i64 %octets, 5; (1 + 5) / 6 == 1
  %sextets = udiv i64 %octets.plus5, 6

  br label %loop

loop:
  %i = phi i64 [0, %entry], [%i.next, %loop]

  %b = extractelement <4 x i6> %chunk, i64 %i
  %c = call i8 @base64.char(i6 %b)

  %out.vec = load <4 x i8>, ptr %out
  %new.out.vec = insertelement <4 x i8> %out.vec, i8 %c, i64 %i
  store <4 x i8> %new.out.vec, ptr %out

  %i.next = add i64 %i, 1
  %is.end = icmp eq i64 %i.next, %sextets
  br i1 %is.end, label %end, label %loop

end:
  ret i64 %sextets
}

define void @pad.if.necessary(ptr %code, i64 %code.size) {
entry:
  br label %check.pad
check.pad:
  %len = phi i64 [%code.size, %entry], [%len.next, %pad]
  %is.four = icmp eq i64 %len, 4
  br i1 %is.four, label %end, label %pad

pad:
  %last.elem = getelementptr i8, ptr %code, i64 %len
  store i8 61, ptr %last.elem

  %len.next = add i64 %len, 1
  br label %check.pad

end:
  ret void
}

define i32 @main() {
entry:
  %buf = alloca <3 x i8>
  %buf.size = add i64 0, 3

  %code = alloca <4 x i8>
  %code.size = add i64 0, 4

  br label %read.stdin

read.stdin:
  store <3 x i8> zeroinitializer, ptr %buf
  %n = call i64 @read(i32 0, ptr %buf, i64 %buf.size)
  %read.end = icmp sle i64 %n, 0
  br i1 %read.end, label %end, label %write.stdout

write.stdout:
  %encoded.len = call i64 @encode(ptr %buf, i64 %n, ptr %code)
  call void @pad.if.necessary(ptr %code, i64 %encoded.len)

  %written = call i64 @write(i32 1, ptr %code, i64 %code.size)
  %write.fail = icmp ne i64 %written, %code.size
  br i1 %write.fail, label %write.error, label %read.stdin

write.error:
  call void @errx(i32 1, ptr @.write.error)
  unreachable

read.error:
  call void @errx(i32 1, ptr @.read.error)
  unreachable

end:
  ret i32 0
}

declare i64 @read(i32, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare void @errx(i32, ptr, ...)

declare <4 x i6> @llvm.vector.reverse.v4i6 (<4 x i6>)
declare <3 x i8> @llvm.vector.reverse.v3i8 (<3 x i8>)
