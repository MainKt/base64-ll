target triple = "x86_64-unknown-freebsd15.0"

@.write.error = constant [16 x i8] c"Unable to write\00"
@.read.error = constant [15 x i8] c"Unable to read\00"
@.bad.char.error = constant [9 x i8] c"Bad char\00"

%Result = type { <48 x i8>, i1 }

define i64 @decoded.len(i64 %size) {
entry:
  %div = udiv i64 %size, 4
  %exact = mul i64 %div, 3
  %rem = urem i64 %size, 4
  %rem.half = udiv i64 %rem, 2
  %extra = sub i64 %rem, %rem.half
  %len = add i64 %exact, %extra

  ret i64 %len
}

define %Result @decode.simd(<64 x i8> %ascii) {
entry:
  %fours = call <64 x i8> @splat(i8 4)
  %shifted = lshr <64 x i8> %ascii, %fours

  %slashes = call <64 x i8> @splat(i8 47); ord('/') == 47
  %eq.i1 = icmp eq <64 x i8> %ascii, %slashes
  %eq = zext <64 x i1> %eq.i1 to <64 x i8>

  %hashes = sub <64 x i8> %shifted, %eq

  %offsets.look.up = call <64 x i8> @tiled(
    <8 x i8> <i8 -1, i8 16, i8 19, i8 4, i8 191, i8 191, i8 185, i8 185>
  )

  %offsets =  call <64 x i8> @swizzle.64i8.64i8(<64 x i8> %offsets.look.up,
    <64 x i8> %hashes)

  %sextets.i8 = add <64 x i8> %ascii, %offsets
  %sextets.reversed = trunc <64 x i8> %sextets.i8 to <64 x i6>
  %sextets = call
    <64 x i6> @llvm.vector.reverse.v64i6(<64 x i6> %sextets.reversed)

  %sextets.bytes.reversed = bitcast <64 x i6> %sextets to <48 x i8>
  %sextets.bytes = call
    <48 x i8> @llvm.vector.reverse.v48i8(<48 x i8> %sextets.bytes.reversed)

  %result.0 = insertvalue %Result undef, <48 x i8> %sextets.bytes, 0

  ; invalid chars check
  %lo.lut = add <16 x i8> zeroinitializer,
    <i8 21, i8 17, i8 17, i8 17, i8 17, i8 17, i8 17, i8 17,
      i8 17, i8 17, i8 19, i8 26, i8 27, i8 27, i8 27, i8 26>
  %fifteens = call <64 x i8> @splat(i8 15)
  %lo.mask = and <64 x i8> %ascii, %fifteens
  %lo = call <64 x i8> @swizzle.16i8.64i8(<16 x i8> %lo.lut, <64 x i8> %lo.mask)

  %hi.lut = add <16 x i8> zeroinitializer,
    <i8 16, i8 16, i8 1, i8 2, i8 4, i8 8, i8 4, i8 8,
      i8 16, i8 16, i8 16, i8 16, i8 16, i8 16, i8 16, i8 16>
  %hi.mask = lshr <64 x i8> %ascii, %fours
  %hi = call <64 x i8> @swizzle.16i8.64i8(<16 x i8> %hi.lut, <64 x i8> %hi.mask)

  %lo.and.hi = and <64 x i8> %lo, %hi
  %reduce.or = call i8 @llvm.vector.reduce.or.v64i8(<64 x i8> %lo.and.hi)
  %is.valid = icmp eq i8 %reduce.or, 0

  %result = insertvalue %Result %result.0, i1 %is.valid, 1

  ret %Result %result
}

define i1 @decode(ptr %buf, ptr %out) {
entry:
  %ascii = load <64 x i8>, ptr %buf
  %result = call %Result @decode.simd(<64 x i8> %ascii)

  %decoded = extractvalue %Result %result, 0
  store <48 x i8> %decoded, ptr %out

  %is.valid = extractvalue %Result %result, 1
  ret i1 %is.valid
}

define i64 @unpad(ptr %buf, i64 %size) {
entry:
  %is.bad.size = icmp eq i64 %size, 0
  br i1 %is.bad.size, label %bad.size.end, label %check

bad.size.end:
  ret i64 0

check:
  %i = phi i64 [1, %entry], [2, %unpad]
  %new.size.0 = phi i64 [%size, %entry], [%last.i, %unpad]
  %last.i = sub i64 %size, %i
  %last = getelementptr i8, ptr %buf, i64 %last.i
  %last.val = load i8, ptr %last
  %is.padding = icmp eq i8 %last.val, 61; int('=') == 61
  br i1 %is.padding, label %unpad, label %end

unpad:
  store i8 65, ptr %last; int('A') == 65
  %is.end = icmp eq i64 %i, 2
  br i1 %is.end, label %end, label %check

end:
  %new.size = phi i64 [%new.size.0, %check], [%last.i, %unpad]
  ret i64 %new.size
}

define i64 @remove.ending.newline(ptr %buf, i64 %size) {
entry:
  %last.i = sub i64 %size, 1
  %last = getelementptr i8, ptr %buf, i64 %last.i
  %last.val = load i8, ptr %last
  %is.newline = icmp eq i8 %last.val, 10

  br i1 %is.newline, label %remove.newline, label %no.change

remove.newline:
  store i8 65, ptr %last; 65 == 'A'
  ret i64 %last.i
  
no.change:
  ret i64 %size
}

define i32 @main() {
entry:
  %buf = alloca <64 x i8>
  %size = add i64 0, 16
  br label %read.stdin

read.stdin:
  %as = call <64 x i8> @splat(i8 65)
  store <64 x i8> %as, ptr %buf
  %n = call i64 @read(i32 0, ptr %buf, i64 %size)
  %read.end = icmp sle i64 %n, 0
  br i1 %read.end, label %end, label %decode

decode:
  %n.0 = call i64 @remove.ending.newline(ptr %buf, i64 %n)
  %non.padded.len = call i64 @unpad(ptr %buf, i64 %n.0)
  %is.valid = call i1 @decode(ptr %buf, ptr %buf)
  br i1 %is.valid, label %write.stdout, label %err.bad.char

write.stdout:
  %decoded.len = call i64 @decoded.len(i64 %non.padded.len)
  %written = call i64 @write(i32 1, ptr %buf, i64 %decoded.len)
  %write.fail = icmp ne i64 %written, %decoded.len
  br i1 %write.fail, label %write.error, label %read.stdin

err.bad.char:
  call void @errx(i32 1, ptr @.bad.char.error)
  unreachable

write.error:
  call void @errx(i32 1, ptr @.write.error)
  unreachable

read.error:
  call void @errx(i32 1, ptr @.read.error)
  unreachable

end:
  ret i32 0
}

define <64 x i8> @splat(i8 %value) {
entry:
  %s.0 = insertelement <64 x i8> undef, i8 %value, i32 0
  %s = shufflevector <64 x i8> %s.0, <64 x i8> undef, <64 x i32> zeroinitializer
  ret <64 x i8> %s
}

define <64 x i8> @tiled(<8 x i8> %v) {
entry:
  %tiles = alloca [8 x <8 x i8>]
  %size = add i64 0, 64
  br label %loop

loop:
  %i = phi i64 [0, %entry], [%i.next, %loop]

  %tiles.i = getelementptr <8 x i8>, ptr %tiles, i64 %i
  store <8 x i8> %v, ptr %tiles.i

  %i.next = add i64 %i, 1
  %is.end = icmp eq i64 %i, %size
  br i1 %is.end, label %end, label %loop

end:
  %tiled = load <64 x i8>, ptr %tiles
  ret <64 x i8> %tiled
}

define <64 x i8> @swizzle.16i8.64i8(<16 x i8> %look.up, <64 x i8> %v) {
entry:
  %size = add i64 0, 16
  br label %loop

loop:
  %i = phi i64 [0, %entry], [%i.next, %loop]
  %values.old = phi <64 x i8> [undef, %entry], [%values, %loop]

  %v.i =  extractelement <64 x i8> %v, i64 %i
  %look.up.i =  extractelement <16 x i8> %look.up, i8 %v.i
  %values =  insertelement <64 x i8> %values.old, i8 %look.up.i, i64 %i

  %i.next = add i64 %i, 1
  %is.end = icmp eq i64 %i, %size
  br i1 %is.end, label %end, label %loop

end:
  ret <64 x i8> %values
}

define <64 x i8> @swizzle.64i8.64i8(<64 x i8> %look.up, <64 x i8> %v) {
entry:
  %size = add i64 0, 16
  br label %loop

loop:
  %i = phi i64 [0, %entry], [%i.next, %loop]
  %values.old = phi <64 x i8> [undef, %entry], [%values, %loop]

  %v.i =  extractelement <64 x i8> %v, i64 %i
  %look.up.i =  extractelement <64 x i8> %look.up, i8 %v.i
  %values =  insertelement <64 x i8> %values.old, i8 %look.up.i, i64 %i

  %i.next = add i64 %i, 1
  %is.end = icmp eq i64 %i, %size
  br i1 %is.end, label %end, label %loop

end:
  ret <64 x i8> %values
}

declare i64 @read(i32, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare void @errx(i32, ptr, ...)

declare <64 x i6> @llvm.vector.reverse.v64i6(<64 x i6>)
declare i8 @llvm.vector.reduce.or.v64i8(<64 x i8>)
declare <48 x i8> @llvm.vector.reverse.v48i8(<48 x i8>)
