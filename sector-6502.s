
;----------------------------------------------------------------------
;   MilliForth for 6502 
;
;   original for the 6502, by Alvaro G. S. Barcellos, 2023
;
;   https://github.com/agsb 
;   see the disclaimer file in this repo for more information.
;
;   SectorForth and MilliForth was made for x86 arch 
;   and uses full 16-bit registers 
;
;   The way at 6502 is use a page zero and lots of lda/sta bytes
;
;   Focus in size not performance.
;
;   Changes:
;   data and return stacks and tib are 256 bytes 
;   only immediate flag used as $80, no hide, no compile, no extras
;
;   Forth-1994:
;   FALSE is $0000
;   TRUE  is $FFFF
;
;----------------------------------------------------------------------
; for ca65 
.p02
.feature c_comments
.feature string_escapes
.feature org_per_seg
.feature dollar_is_pc
.feature pc_assignment

;---------------------------------------------------------------------
; label for primitives
.macro makelabel arg1, arg2
.ident (.concat (arg1, arg2)):
.endmacro

H0000 = 0
hcount .set 0

; header for primitives
.macro def_word name, label, flag
;this = *
makelabel "is_", label
    .ident(.sprintf("H%04X", hcount + 1)) = *
	.word .ident (.sprintf ("H%04X", hcount))
    hcount .set hcount + 1
    .byte .strlen(name) + flag + 0
    .byte name
makelabel "", label
.endmacro

;----------------------------------------------------------------------
; alias
CELL   =  2     ; 16 bits
SIZES  = $100

FLAG_IMM  =  1<<7

;----------------------------------------------------------------------
.segment "ZERO"

* = $E0
; default pseudo registers
nil:    .word $0 ; reference, do not touch ! 
lnk:    .word $0 ; link, do not touch !
dta:    .word $0 ; holds data stack base,
ret:    .word $0 ; holds return stack base,

; default Forth pseudo registers
tos:    .word $0 ; top
nos:    .word $0 ; nos
wrk:    .word $0 ; work
tmp:    .word $0 ; temp

; default Forth variables
state:  .word $0 ; state
toin:   .word $0 ; toin
last:   .word $0 ; last link cell
here:   .word $0 ; next free cell

;----------------------------------------------------------------------
.segment "ONCE" 

;----------------------------------------------------------------------
.segment "VECTORS" 

;----------------------------------------------------------------------
.segment "CODE" 

;---------------------------------------------------------------------
main:

    ; latest link
    lda #<semis
    sta last + 0
    lda #>semis
    sta last + 1

    ; next free meory cell
    lda #<init
    sta here + 0
    lda #>init
    sta here + 1
    
    ; that does the trick
    lda #<nil
    sta nil + 0
    lda #>nil
    sta nil + 1

error:

	lda #13
	jsr putchar

;---------------------------------------------------------------------
quit:

    ; reset data stack
    lda #<dsb
    sta dta + 0
    lda #>dsb
    sta dta + 1

    ; reset return stack
    lda #<rsb
    sta ret + 0
    lda #>rsb
    sta ret + 1
    
    ; clear tib stuff
    ldy #0
    sty toin + 0
    sty toin + 1
    sty tib + 0

    ; state interpret
    iny   
    sty state + 0

;---------------------------------------------------------------------
find:

    ; get a token, (nos)
    jsr tok_
  
    ; load lastest link
    lda #<last
    sta wrk + 0
    lda #>last
    sta wrk + 1

@loop:

    ; linked list
    lda wrk + 0
    sta tos + 0
    lda wrk + 1
    sta tos + 1
    
    ldx #(tos - nil)
    ldy #(wrk - nil)
    jsr pull

    ; verify is zero
    lda wrk + 0
    ora wrk + 1
    beq error ; end of dictionary, no more words

    ; bypass link
    ldx #(tos - nil)
    jsr incw
    jsr incw

    ; compare words
    ; must mask the flags at size byte
    ldy #0
    lda (tos), y
    and #$80
    sta wrk + 0

@equal:
    lda (nos), y
    cmp #32     
    beq @done
    ; verify 
    sbc (tos), y
    and #$7F    ; 7-bit ascii, also mask flag
    bne @loop
    ; next
    iny
    bne @equal
@done:
    
    ; update 
    tya
    ldx #(tos - nil)
    jsr add2w

    ; compile or execute
    lda wrk + 0     ; immediate ? 
    bne @execw

    lda state + 0   ; executing ?
    bne @execw

    jmp compile

@execw:

    jmp next_

;---------------------------------------------------------------------
getline_:
    ; leave a space
    ldy #1
@loop:  
	jsr getchar
	cmp #10         ; lf ?
	beq @endline
    ;	cmp #13     ; cr ?
	;   beq @ends
    ;   cmp #8      ; bs ?
    ;   bne @puts
    ;   dey
    ;   jmp @loop
@puts:
    and #$7F        ; 7-bit ascii
    sta tib, y
    iny
    ;   cpy #254
    ;   beq @ends   ; leave ' \0'
	bne @loop
@endline:
    ; grace 
    lda #32
    sta tib + 0 ; start with space
    sta tib, y  ; ends with space
    iny
    lda #0      ; mark end of line
    sta tib, y
    ; reset line
    sta toin + 1
    rts

;---------------------------------------------------------------------
try_:
    lda tib, y
    beq newline    ; if \0 
    iny
    cmp #32
    rts

newline:
    jsr getline_

tok_:
    ; last position on tib
	ldy toin + 1

@skip:
    ; skip spaces
    jsr try_
    beq @skip

    ; keep start 
    dey
    sty toin + 0    

@scan:
    ; scan spaces
    jsr try_
    bne @scan

    ; keep stop 
    dey
    sty toin + 1    ; save position

    ; strlen
    sec
    lda toin + 1
    sbc toin + 0

    ; place strlen
    dec toin + 0
    dey
    sta tib, y    ; store size ahead 

    ; update
    sty nos + 0
    lda #>tib
    sta nos + 1

    rts

;---------------------------------------------------------------------

; add a byte to a word in page zero. offset by X
; increment a word in page zero, offset by X
incw:
    lda #1
; add a byte to a word in page zero. offset by X
add2w:
    clc
    adc nil + 0, x
    sta nil + 0, x
    bcc @noinc
    inc nil + 1, x
@noinc:
    rts

; decrement a word in page zero. offset by X
decw:
    lda nil + 0, x
    bne @nodec
    dec nil + 1, x
@nodec:
    dec nil + 0, x
    rts

; pull a word 
; from a page zero address indexed by X
; into a absolute page zero address indexed by y
pull:
    lda (nil, x)    
    sta nil + 0, y   
    jsr incw        
    lda (nil, x)    
    sta nil + 1, y  
    jmp incw

; push a word 
; from an absolute page zero address indexed by Y
; into a page zero address indexed by X
push:
    jsr decw
    lda nil + 1, y
    sta (nil, x)
    jsr decw
    lda nil + 0, y
    sta (nil, x)
    rts

; push into data stack
spush:
    ldx #(dta - nil)
    ldy #(tos - nil)
    bne push

; pull from data stack
spull:
    ldx #(dta - nil)
    ldy #(tos - nil)
    bne pull

spull2:
    jsr spull 
dta2nos:
    ; ldx #(dta - nil)
    ldy #(nos - nil)
    bne pull

; fetch from
; store into

;---------------------------------------------------------------------
; for lib6502  emulator
getchar:
    lda $E000

putchar:
    sta $E000
    rts

;---------------------------------------------------------------------
; primitives ends with jmp link_
;
;def_word "emit", "emit", 0
;   jsr spull
;   lda tos + 0
;   jsr putchar
;   jmp link_
;
;def_word "key", "key", 0
;   jsr getchar
;   sta tos + 0
;   jsr spush
;   jmp link_
;
;---------------------------------------------------------------------
def_word "!", "store", 0
storew:
    jsr spull2
    ldx #(tos - nil)
    ldy #(nos - nil)
    jsr push
    jmp link_

;---------------------------------------------------------------------
def_word "@", "fetch", 0
fetchw:
    jsr dta2nos
    ldx #(nos - nil)
    ldy #(tos - nil)
    jsr pull
    jmp topsh

;---------------------------------------------------------------------
def_word "s@", "statevar", 0 
    lda #<state
    sta tos + 0
    lda #>state
back:
    sta tos + 1
topsh:
    jsr spush
    jmp link_

;---------------------------------------------------------------------
def_word "rp@", "rpfetch", 0
    lda ret + 0
    sta tos + 0
    lda ret + 1
    jmp back

;---------------------------------------------------------------------
def_word "sp@", "spfetch", 0
    lda dta + 0
    sta tos + 0
    lda dta + 1
    jmp back

;---------------------------------------------------------------------
def_word "+", "plus", 0
    jsr spull2
    clc
    lda nos + 0
    adc tos + 0
    sta tos + 0
    lda nos + 1
    adc tos + 1
    jmp back

;---------------------------------------------------------------------
def_word "nand", "nand", 0
    jsr spull2
    lda nos + 0
    and tos + 0
    eor #$FF
    sta tos + 0
    lda nos + 1
    and tos + 1
    eor #$FF
    jmp back

;---------------------------------------------------------------------
def_word "0=", "zeroq", 0
    jsr spull
    lda tos + 0
    ora tos + 1
    beq istrue
isfalse:
    lda #$0
    beq rest
istrue:
    lda #$FF
rest:    
    sta tos + 0
    jmp back

;def_word "shr", "shr", 0
;    jsr spull
;    lsr tos + 1
;    ror tos + 0
;    jmp spush

;---------------------------------------------------------------------
; minimal indirect thread code
; lnk must be preserved, as IP
;
def_word "exit", "exit", 0
unnest_:
    ; pull from return stack
    ldx #(ret - nil)
    ldy #(tos - nil)
    jsr pull

next_:
    ldx #(tos - nil)
    ldy #(lnk - nil)
    jsr pull

    ; is a primitive ? 
    lda lnk + 1
    cmp #$08    ; magic high byte of init: not generic!
    bcc jump_

nest_:
; push into return stack
    ldx #(ret - nil)
    ldy #(tos - nil)
    jsr push

link_:
    lda lnk + 0
    sta tos + 0
    lda lnk + 1
    sta tos + 1
    jmp next_

jump_:
    ldx #(ret - nil)
    ldy #(lnk - nil)
    jsr pull
    jmp (tos)

;---------------------------------------------------------------------
def_word ":", "colon", 0
    ; save here, for update last later

    ldx #(dta - nil)
    ldy #(here - nil)
    jsr push

    ; update the link field with last

    ldx #(here - nil)
    ldy #(last - nil)
    jsr push

    ; get the token, at nos
	jsr tok_

    ;copy size and name ????
    ldy #0
@loop:    
    lda (nos), y
    cmp #32     ; stops at space
    beq @endname
    sta (here), y
    iny
    bne @loop
@endname:

    ; update here
    tya
    ldx #(here - nil)
    jsr add2w

    ; update state as 'compile'

	lda #0
    sta state + 0
    
    jmp link_

;---------------------------------------------------------------------
def_word ";", "semis", FLAG_IMM

    ; update last

    ldx #(dta - nil)
    ldy #(last - nil)
    jsr pull

    ; update state as 'interpret'
	lda #1
    sta state + 0

    ; compounds ends with 'unnest'
    lda #<unnest_
    sta tos + 0
    lda #>unnest_
    sta tos + 1

compile:
    
    ldx #(here - nil)
    ldy #(tos - nil)
    jsr push
    jmp link_

;---------------------------------------------------------------------
ends:

; debug stuff
.if 0

erro:
    lda #'?'
    jsr putchar
    lda #'?'
    jsr putchar
	lda #10
	jsr putchar
	lda #13
	jsr putchar
    rts

okey:
    lda #'O'
    jsr putchar
    lda #'K'
    jsr putchar
	lda #10
	jsr putchar
	lda #13
	jsr putchar
    rts

.endif


.align $100

; $200 to $2FF terminal input buffer
tib:
.res SIZES, $0   

; $3FF to $300 return stack base, 128w deep
.res SIZES, $0
rsb:            

; $4FF to $400 data stack base, 128w deep
.res SIZES, $0
dsb:            

; for anything above is not a primitive
; * = $800
init:   

