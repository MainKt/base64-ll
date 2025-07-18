target triple = "x86_64-unknown-freebsd15.0"

@.write.error = constant [16 x i8] c"Unable to write\00"
@.read.error = constant [15 x i8] c"Unable to read\00"
@.bad.char.error = constant [9 x i8] c"Bad char\00"

define i8 @sextet(i8 %byte) {
upper.check:
  %is.upper.0 = icmp uge i8 %byte, 65; 'A'
  %is.upper.1 = icmp ule i8 %byte, 90; 'Z'
  %is.upper = and i1 %is.upper.0, %is.upper.1
  br i1 %is.upper, label %upper, label %lower.check

upper:
  %upper.ret = sub i8 %byte, 65
  ret i8 %upper.ret

lower.check:
  %is.lower.0 = icmp uge i8 %byte, 97; 'a'
  %is.lower.1 = icmp ule i8 %byte, 122; 'z'
  %is.lower = and i1 %is.lower.0, %is.lower.1
  br i1 %is.lower , label %lower, label %num.check

lower:
  %lower.ret.i8.0 = sub i8 %byte, 97
  %lower.ret = add i8 %lower.ret.i8.0, 26
  ret i8 %lower.ret

num.check:
  %is.num.0 = icmp uge i8 %byte, 48; '0'
  %is.num.1 = icmp ule i8 %byte, 57; '9'
  %is.num = and i1 %is.num.0, %is.num.1
  br i1 %is.num, label %num, label %plus.check

num:
  %num.ret.i8.0 = sub i8 %byte, 48
  %num.ret = add i8 %num.ret.i8.0, 52
  ret i8 %num.ret

plus.check:
  %is.plus = icmp eq i8 %byte, 43; '+'
  br i1 %is.plus, label %plus, label %slash.check

plus:
  ret i8 62; '+'

slash.check:
  %is.slash = icmp eq i8 %byte, 47; '/'
  br i1 %is.slash, label %slash, label %error

slash:
  ret i8 63; '/'
error:
  ret i8 -1
}

define i64 @decode(ptr %buf, i64 %size) {
entry:
  %chunk = load <4 x i8>, ptr %buf

  br label %loop

loop:
  %i = phi i64 [0, %entry], [%i.next, %cast.sextet]

  %b = extractelement <4 x i8> %chunk, i64 %i
  %s.i8 = call i8 @sextet(i8 %b)
  %is.bad.char = icmp eq i8 %s.i8, -1

  br i1 %is.bad.char, label %err.bad.char, label %cast.sextet

err.bad.char:
  call void @errx(i32 1, ptr @.bad.char.error)
  unreachable

cast.sextet:
  %s = trunc i8 %s.i8 to i6

  %out.vec = load <4 x i6>, ptr %buf
  %new.out.vec = insertelement <4 x i6> %out.vec, i6 %s, i64 %i
  store <4 x i6> %new.out.vec, ptr %buf

  %i.next = add i64 %i, 1
  %is.end = icmp eq i64 %i.next, %size
  br i1 %is.end, label %end, label %loop

end:
  %v.4xi6 = load <4 x i6>, ptr %buf
  %v.4xi6.reversed = call <4 x i6> @llvm.vector.reverse.v4i6 (<4 x i6> %v.4xi6)

  %v.reversed = bitcast <4 x i6> %v.4xi6.reversed to <3 x i8>
  %v = call <3 x i8> @llvm.vector.reverse.v3i8 (<3 x i8> %v.reversed)
  store <3 x i8> %v, ptr %buf

  %div = udiv i64 %size, 4
  %exact = mul i64 %div, 3
  %rem = urem i64 %size, 4
  %rem.half = udiv i64 %rem, 2
  %extra = sub i64 %rem, %rem.half
  %len = add i64 %exact, %extra

  ret i64 %len
}

define i64 @unpadded.len(ptr %buf, i64 %size) {
entry:
  br label %unpad

unpad:
  %unpadded.len = phi i64 [%size, %entry], [%last.i, %remove.end]
  %last.i = sub i64 %unpadded.len, 1
  %is.oob = icmp slt i64 %last.i, 0
  br i1 %is.oob, label %end, label %remove.end

remove.end:
  %last = getelementptr i8, ptr %buf, i64 %last.i
  %last.val = load i8, ptr %last
  %is.padding = icmp eq i8 %last.val, 61; int('=') == 61

  br i1 %is.padding, label %unpad, label %end

end:
  ret i64 %unpadded.len
}

define i32 @main() {
entry:
  %buf = alloca <4 x i8>
  %size = add i64 0, 4
  br label %read.stdin

read.stdin:
  %n = call i64 @read(i32 0, ptr %buf, i64 %size)
  %read.end = icmp sle i64 %n, 0
  br i1 %read.end, label %end, label %write.stdout

write.stdout:
  %non.padded.len = call i64 @unpadded.len(ptr %buf, i64 %n)
  %decoded.len = call i64 @decode(ptr %buf, i64 %non.padded.len, ptr %buf)

  %written = call i64 @write(i32 1, ptr %buf, i64 %decoded.len)
  %write.fail = icmp ne i64 %written, %decoded.len
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
