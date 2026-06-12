; Purpose: Zombies ate my Neighbors Modified HUD writer, Blood Hack, High Score Save
; Date: 09 May 2017
; Author: DackR
; Notes: Converted to asar (built via retrotool). Previously xkas-plus.
;        Fixed coin-up routine so that inserting coins no longer triggers multiple coins
;
; asar dialect notes (vs the old xkas-plus source):
;   - defines are !name = value, referenced as !name
;   - org takes a full 24-bit SNES address (bank 00 for the header-area tables)
;   - MVN operand order is swapped: asar is "mvn dest,src" (matching the
;     machine-code byte order), xkas-plus was "mvn src,dest"

lorom

;variables...
; Scratch vars relocated 2026-06-10: they used to live at $7e1d3e-$7e1d48,
; which is INSIDE the game's per-player item-count arrays (P1 $1d0c-$1d2b,
; P2 $1d2c-$1d4b, right up against playerLives at $1d4c). In 2P mode the
; old addresses corrupted P2's inventory: aVar ($1d42) = P2 item 11 count,
; demoSceneChecker ($1d44) = P2 phantom item 12 count (= lives, counted
; down on death). $7e5e00-$5ef9 has no references anywhere in the full
; disassembly (long, absolute, or pointer-immediate), same profile as the
; tile buffer at $5efa that follows it.
!lastcredit = $7e5ee0 ;(last credit status for p1 and p2)
!p2StartDrawn = $7e5ee2
!aVar = $7e5ee4
!demoSceneChecker = $7e5ee6
!PlayerIndex = $7e5ee8
!mapType = $7e5eea
!lastp1keys = $7e5eec ;P1 last-keypress, for coin-up edge detection.
                      ;MUST be long-addressed: evaluatekeys runs with D=$0C00,
                      ;so the original direct-page "$62" hit $0C62:$0C63 and
                      ;corrupted live game state (player went blue-potion/
                      ;upside-down on water transitions while holding buttons).
;(free: $7e5eee-$7e5ef9)
!playerLives = $7e1d4c ;game variable -- do not move
!tileDefLoc = $7e5efa
!playsndsub = $80cc3b ;set A (sfxid) and jsl to this address

; NOTE: $00FF50-$00FF8B is NOT free -- it is the tail of a live animation
; table the game reads via LDA ($14),Y at $80F303/$80F317 (reaches $80FF52+).
; The old hack's lifeTable values there read as harmless deltas; our larger
; border-tile words corrupted player animation (blue-blob/upside-down on
; water transitions). The border tables now live in bank $82 freespace as
; labels (faceTile / hdmaTbl, end of file); p1's box is written inline.
!livesTileMap = $ffa0
!demoTileMap = $ffb0

;Indicate ROM + RAM + SRAM
org $00ffd6
db $02

;2kb SRAM
org $00ffd8
db $01

org $96f121
incbin "../bin/0xB7121.bin"

org $8fcc00
incbin "../bin/0x7CC00_InsertCoin.bin"

; number of tiles, and tile defs for LIVES: (still used by the P2 legacy text)
org $00ffa0 ;!livesTileMap
db $0c,$00,$9B,$3C,$98,$3C,$A5,$3C,$94,$3C,$A2,$3C,$8F,$3C,$00,$00
; tile definition for DEMO MODE
;org $00ffb0 ;!demoTileMap
db $12,$00,$93,$3C,$94,$3C,$9C,$3C,$9E,$3C,$00,$00,$9C,$3C,$9E,$3C
db $93,$3C,$94,$3c,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; Blood hack...
org $808b89    ;PC $0B89
lda #$13    ;#$53
sta $2122
lda #$00    ;#$59
sta $2122
lda #$0D    ;#$8a
sta $2122
lda #$00    ;#$34
sta $2122
lda #$0A    ;#$26
sta $2122
lda #$00    ;#$1c
sta $2122

;write blood/monster palette
org $9e9026
db $15,$00,$13,$00,$0F,$00,$0C,$00,$09,$00

;Adding some code to the HUD DMA transfer...
org $80c34a ; 44 bytes long (2C)
jml dmahud
;rep 40 : nop ;TODO: should add more nops since i've skipped the next transfer

; Hijacking death (lives--) code for hud generation
org $80cec5
jml playerdeathentry
nop

; This is the keypress evaluation routine
org $8089b0
jml evaluatekeys
nop
nop
;return to $8089b6

; Hijack beginning of level...
org $80866a
jml levelentry

; Hijack 1up routine
org $80fa68
jml oneupentry

; Palette change for 1p or 2p modes
org $80873f
jml palchange

; Music change for 1p or 2p modes
org $82ac56
jml musicchange

;Change press start to insert coin... conditionally... this is gonna suck
;org $80b960
;jml gfxdma

;hijacking high score table initialization in wram...
org $82bb13
jml makescoretable
;rep 8 : nop

;hijacking high score save
org $82bd2f
jml xferscore
;rep 2 : nop

;slight noise change... just for fun
org $809735
lda #$0026

;hook the NMI's INIDISP-from-shadow write (LDA $136C / STA $2100 at $0081AB):
;runs only on real rendered frames (the lag-frame/loading early-out path is
;upstream), and the shadow's bit7 tells us forced blank -- never re-arm HDMA
;while the game has the screen blanked for loading (doing so fired stale
;HDMA tables over the level-intro screens)
org $8081AB
jml nmithunk
nop
nop

org $82f980
p1coinupentry:
lda #$0003
sta !mapType
ldx #$0000    ;this is the player index we need
jmp makelifemap

levelentry:
jsr drawstatic ;face tile + static border cells (level load = screen blanked)
lda #$0001  ;entry point for beginning of level
sta !mapType
lda #$0000
sta !p2StartDrawn
jmp makelifemap

playerdeathentry:
lda #$0000  ; entry point for death
sta !mapType
jmp makelifemap

oneupentry:
phy
ldx $0e       ; this is the variable the game uses for the player index
sed           ; set decimal mode
clc           ; clear carry flag
lda $001e72,x ; load the current score
adc #$0001    ; add one (decimal mode)
sta $001e72,x ; this will force the GUI to update.. just adding 1 to score.
cld           ; turn off decimal mode
lda #$0002
sta !mapType
jmp makelifemap

; This section actually generates the lives counter
makelifemap:
jsr drawsides ; border side edges for HUD rows 24-26 (idempotent)
txa ; transfer the player index...
sta !PlayerIndex ; store the player currently being handled (0,2) [P1,P2]
cmp #$0002
bne p1map
beq p2map

p1map: ; P1: bordered box top edge (cols 2-15), face + count in the break.
       ; Written inline (no ROM table) -- store is long-addressed/DBR-safe, and
       ; this keeps the data out of the game's animation-table region. Border
       ; = pal4 greyscale ($30xx), break caps v-flipped ($B0B7/$F0B7), face +
       ; count stay pal7 ($3Cxx). Dest cells land at tileDefLoc+0,2,4,...,1A.
ldx #$0000
lda #$30B1 : jsr store ; col2  h-edge
lda #$B0B7 : jsr store ; col3  break cap (left)
lda #$3CC0 : jsr store ; col4  FACE icon
lda #$3C00 : jsr store ; col5  count cell (overwritten by numgen, offset 6)
lda #$F0B7 : jsr store ; col6  break cap (right)
lda #$30B1 : jsr store ; col7  h-edge
lda #$30B1 : jsr store ; col8
lda #$30B1 : jsr store ; col9
lda #$30B1 : jsr store ; col10
lda #$30B1 : jsr store ; col11
lda #$30B1 : jsr store ; col12
lda #$30B1 : jsr store ; col13
lda #$30B1 : jsr store ; col14
lda #$70B0 : jsr store ; col15 top-right corner
ldy #$0006 ; fixed buffer offset of the count cell inside the break
jmp numgen

p2map: ; P2: legacy LIVES:n text for now (P2 box is milestone 2)
ldx #$0020
ldy #$0002 ; start reading past the number
repeatmap: ; copy the Lives: tiles to RAM
lda !livesTileMap,y
jsr store
cpy !livesTileMap ;are we at the last tile?
bcs p2digit
iny
iny
jmp repeatmap
p2digit:
txy ; legacy behavior: digit goes right after the text
jmp numgen

p1coinup:
jml normalkeys

;generate map for lives left # here... (Y = buffer offset for the digit)
numgen:
lda !PlayerIndex       ; use current player index
tax
lda #$0000
cmp !playerLives,x		 ; **this is the game variable for # of lives left
beq foundzero
sta !aVar
incloop:
lda !aVar
inc
cmp !playerLives,x		  ; **this is the game variable for # of lives left
beq foundnum
sta !aVar
lda #$000a
cmp !playerLives,x		  ; **this is the game variable for # of lives left
bpl incloop            ; number of lives less than 9 (since we haven't -- yet)
bmi foundplus          ; number of lives is greater than 9

endmapgen:
lda #$0003 ;p1 coin-up
cmp !mapType
beq p1coinup
lda #$0002 ;found one-up
cmp !mapType
beq oneupinc
lda #$0000
cmp !mapType		  ; **this varaible contains 0=death, 1=lvl start
bne levelstart   ; if this isnt generated from a death, then branch w/o --
                  ; otherwise... its a death.
isdeath:
lda !PlayerIndex
tax
lda !playerLives,x		; **this is the game variable for # of lives left
cmp #$0000
beq isneg ; only game over if we are about to go negative
dec			            ; --
sta !playerLives,x		; **this is the game variable for # of lives left
jml $80ceca ;Return back to the main routine

foundzero:
jmp gameover

isneg:
jml $80ced5 ; this triggers player game over

drawp1tiles:
ldx #$0000
jml makelifemap

drawp2tiles:
ldx #$0002
lda #$0001
sta !p2StartDrawn
jml makelifemap

foundnum:
tyx
jsr numstore
jmp endmapgen

foundplus:	; Number of lives is greater than 9... kinda lazy
tyx
jsr numstoreplus
jmp endmapgen

levelstart:
lda !PlayerIndex
tax
lda !playerLives,x
sta !demoSceneChecker ; this is so we can tell if the lives dec without death
;check to see if we need to draw some MOAR
lda !PlayerIndex
cmp #$0002
beq drawp1tiles ;still need to do P1, yo

;this is a check to see if p2 hud update is still needed
;check if p1 has lives...
lda !PlayerIndex
cmp #$0000
bne alldonestart
lda !playerLives,x
cmp #$0000
bne alldonestart
lda !p2StartDrawn
cmp #$0000
beq drawp2tiles ;map up player two

alldonestart:
jml $80c2da ;back to level start

oneupinc:
;phx
;phy
;lda #$0666
;sta !aVar
;jml startdma ;force dma transfer??
oneupdone:
ply
ldx $0e
lda $001d4c,x
jml $80fa6e

store:	; store the tile definition in WRAM
sta !tileDefLoc,x
inx
inx
rts

drawsides: ; greyscale border side edges, HUD rows 24-26 cols 0 and 15
lda #$30B2
sta.l $7e5f36
sta.l $7e5f76
sta.l $7e5fb6
lda #$70B2
sta.l $7e5f54
sta.l $7e5f94
sta.l $7e5fd4
rts

drawstatic: ; level start (screen blanked): face tile + border cells the
            ; HUD DMA window never covers (row 23 cols 0-1, all of row 27)
php
sep #$20
lda #$80
sta $2115 ; increment on $2119 write
rep #$20
ldy #$4600 ; face icon -> VRAM tile $C0
sty $2116
ldx #$0000
facecopy:
lda.l faceTile,x
sta $2118
inx
inx
cpx #$0010
bcc facecopy
ldy #$66e0 ; row 23 cols 0-1: top-left corner + h-edge
sty $2116
lda #$30b0
sta $2118
lda #$30b1
sta $2118
ldy #$6760 ; row 27: bottom edge, corners v-flipped
sty $2116
lda #$b0b0
sta $2118
ldx #$000e
botloop:
lda #$b0b1
sta $2118
dex
bne botloop
lda #$f0b0
sta $2118
plp
rts

nmithunk: ; NMI rendered-frame path, vblank, 8-bit M, registers saved
lda.l $7e136c ; INIDISP shadow (displaced original: LDA $136C / STA $2100)
sta.l $002100
bmi nmiskip   ; bit7 = forced blank (loading) -> leave HDMA untouched
rep #$20
lda #$2801
sta.l $004310 ; ch1: mode 1, B-bus $2128/$2129
lda.w #hdmaTbl
sta.l $004312 ; HDMA source addr (low 16)
sep #$20
lda.b #hdmaTbl>>16
sta.l $004314 ; HDMA source bank ($82)
lda.l $7e136e
ora #$02
sta.l $00420c ; HDMA enable: game's channels + our ch1, re-armed every frame
nmiskip:
jml $8081b1   ; resume the NMI body (M stays 8-bit on both paths)

; --- border data tables (relocated to bank $82 freespace; see note at top) ---
; face icon (2bpp): orange hair / skin / black eyes, drawn into VRAM tile $C0
faceTile:
db $00,$7E,$00,$FF,$6C,$93,$7E,$81,$7E,$28,$7E,$00,$3C,$18,$18,$00
; HDMA table for ch1, mode 1 -> $2128/$2129 (color window 2 left/right):
; W2 empty except scanlines 189-215 = [7,120], the box interior (user-tuned).
hdmaTbl:
db $7F,$FF,$00 ; lines 0-126: empty
db $3E,$FF,$00 ; lines 127-188: empty
db $1B,$07,$78 ; lines 189-215: W2=[7,120] (+1px L/R, +3px top)
db $08,$FF,$00 ; lines 216-223: empty
db $00

numstore:	; pretty much like "store", but handles numbers
dec
dec
adc #$3c07	; adding the value of the tile representing "0"
   			    ; clear carry because... we dont want anything extra next adc
sta !aVar
lda !mapType ; add one if we are starting the level
cmp #$0001
bcs addone

lda !aVar
bra addnone

addone:
lda !aVar
clc
adc #$0001
bra addnone

addnone:
cmp #$3c11	; ****this might need to be modified...
bcs numstoreplus ; if we have more than 9 now.. do 9+
sta !tileDefLoc,x
inx
inx
rts ; (old zero-terminator removed -- it would wipe the break's right cap)

numstoreplus:
lda #$3c10
sta !tileDefLoc,x
inx
inx
lda #$3c8e
sta !tileDefLoc,x
inx
inx
rts

gameover:
lda !PlayerIndex
cmp #$0002
bne p1go
beq p2go
p1go:
ldx #$0000
bra allgo
p2go:
ldx #$0020
allgo:
ldy #$0007 ;number of tiles to clear

clearstuff:
lda #$0000
jsr store
dey
cpy #$0000
bpl clearstuff

jmp endmapgen


makescoretable:
lda $700010 ; this tells me if I've initialized the table before
cmp #$0666 ; check to see if the table is already written
beq writewram ; if it exists, copy the sram table to wram

;lda #$0000
;sta $700000

ldx #$0000
ldy #$0001
lda #$07fe ; the number of bytes to clear
mvn $70,$70 ;clear sram (dest $70, src $70)

ldx #$bb2e
ldy #$0020 ;#$2064
lda #$00BC ;instead of just $95, transfer $BC
mvn $70,$82 ;ROM table -> LoROM SRAM (xkas was: mvn $82,$70)

;ldx #$2064
;ldy #$0020
;lda #$00BC
;mvn $7e,$70

lda #$0666  ; this is the value I check for on game start
sta $700010 ; table now exists (if there is SRAM)

;CHECK IF LOROM OR HIROM
lda $700010 ; this is the LOROM SRAM location
cmp #$0666 ; check to see if the table was successfully written
beq writewram ; if it exists, copy the sram table to wram

;THE SRAM WRITE FAILED - TRY HIROM MAPPING
lda $206010 ; this is the HIROM SRAM location for the first 8kb
cmp #$0666 ; check to see if the table is already written
beq writehiwram ; if it exists, copy the sram table to wram

ldx #$6000 ;start source
ldy #$6001 ;start destination
lda #$07fe ; the number of bytes to clear
mvn $20,$20 ;clear sram (dest $20, src $20)

ldx #$bb2e
ldy #$6020 ;#$2064
lda #$00BC ;instead of just $95, transfer $BC
mvn $20,$82 ;ROM table -> HiROM SRAM (xkas was: mvn $82,$20)

lda #$0666  ; this is the value I check for on game start
sta $206010 ; table now exists (if there is SRAM)

;CHECK TO SEE IF HIROM SRAM write was successful--
lda $206010 ; this is the HIROM SRAM location for the first 8kb
cmp #$0666 ; check to see if the table is there
bne nosram ; if it exists, copy the sram table to wram

writehiwram:
ldx #$6020
ldy #$2064
lda #$00BC
mvn $7e,$20 ;HiROM SRAM -> WRAM (xkas was: mvn $20,$7e)

jml $82bb2b ; back to the main init routine

writewram:
ldx #$0020
ldy #$2064
lda #$00BC
mvn $7e,$70 ;LoROM SRAM -> WRAM (xkas was: mvn $70,$7e)

jml $82bb2b ;$82bb1f ; jump back to main init routine

nosram: ;if there is no SRAM, copy the high score table from ROM to WRAM
ldx #$bb2e
ldy #$2064 ;#$2064
lda #$00BC ;instead of just $95, transfer $BC
mvn $7e,$82 ;ROM table -> WRAM (xkas was: mvn $82,$7e)

jml $82bb2b ;$82bb1f ; jump back to main init routine

lifediff:
lda #$0003
sta !mapType ;just write this so we dont waste time writing tilemap again
ldx #$0000
ldy #$0002 ; start reading past the number
repeatdemo:
; copy the DEMO MODE tiles to RAM
lda !demoTileMap,y
jsr store
;tay ;temporarily copy a->y
cpy !demoTileMap ;are we at the last tile?
bcs startdma
iny
iny
jmp repeatdemo

dmahud:
phx ;cause I dont know if it's in use...
phy ;cause I dont know if it's in use...
jsr drawsides ;every frame: the game's HUD builder rebuilds $5F36 and wipes them
lda !PlayerIndex
cmp #$0000
bne startdma
lda !mapType
cmp #$0001
bne startdma
lda !playerLives
cmp !demoSceneChecker
bne lifediff
;!PlayerIndex=0
;if !mapType=1 (scene just loaded)
;check if lives match last known if there were no deaths
;if !mapType is 1 and the lives dont match == demo

startdma:
ply
plx
lda #$1801	; #$01 <- 2 registers, write once
			      ; (writes to low and high register)
			      ; #$18 <- Specify B-Bus register to access..
            ; $00:2118 - (VRAM Data write register)
sta $4300 	; Write to DMA control register and Destination Channel

lda #$5efa	; *Modified* ($5f36)
sta $4302 	; DMA Transfer Source Address
			      ; (DMA control was set earlier to 2 registers, write once)
			      ; ^^Write #$36 to $4302 and #$5f to $4303

lda #$007e 	; #$7e is the bank of the source data being transferred
			      ; ^^^^ This is a WRAM bank
sta $4304  	; DMA Transfer Source Bank Register

lda #$00fc  ; <---Specifying size of transfer *Modified* (#$00c0)
sta $4305 	; DMA Transfer Size Register (Set number of bytes to transfer)

lda #$66e2 	; *Modified* (#$6440) #$6422 <-TOP of Screen
sta $2116 	; VRAM Address register
			      ; (Because of BGmode 3, this Transfer actually writes to $CAE2...)

sep #$20  	; Set CPU flag... 8-bit mode

lda #$80  	; (1000 0000) <- Sets Address increment mode
			      ;  ^ Increments after $2119 (high byte)
			      ;    is written to desination.
			      ;   ^^^ These 3 Bits are unused
			      ;       ^^ No address remapping
			      ;         ^^ Normal increment by one
sta $2115  	; Write #$80 (10000000) to Video Port Control

lda #$01
sta $420b  	; Enable DMA Channel #1 (commence transfer)

rep #$30   	; Back to 16-bit mode

lda !aVar
cmp #$0666
beq returnsub

jml $80c376
;END OF HUD WRITER CODE

returnsub:
jml oneupdone

;COPY SCORE TO SRAM
xferscore:
mvn $7e,$00 ;this is where I hijacked it (original instruction, dest $7e src $00; xkas was: mvn $00,$7e)

;save it to SRAM
ldx #$2064
ldy #$0020
lda #$00BC
mvn $70,$7e ;WRAM -> LoROM SRAM (xkas was: mvn $7e,$70)

;same as old routine exit
plb
plb
rts

;we will be mixing up the palletes for some levels (co-op)
palchange:
cpx #$9060 ; should mean this is level one... maybe
beq palswap

lda $9f0010,x
bra palswapdone

palswap:
lda $7e1d4e
cmp #$0002
bne changedmymind
lda #$9176
bra palswapdone

changedmymind:
lda $9f0010,x

palswapdone:
jml $808743

musicchange:
cpx #$9060 ; should mean this is level one... maybe
beq musicswap

lda $9f0032,x
bra musicchangedone

musicswap:
lda $7e1d4e
cmp #$0002
bne nomusicchange
lda #$000A
bra musicchangedone

nomusicchange:
lda $9f0032,x

musicchangedone:
jml $82ac5a

;hyjacking the dma of most sprites, backgrounds so we can redirect certain gfx
;gfxdma:
;cpy #$0040
;beq
;lda $15de,x ;source address, low byte, high byte
;sta $4302
;lda $165e,x ;source address, bank byte (word form)
;sta $4304
;sty $4305   ; y holds the size of the transfer... (looks like it depends on a different table)
;lda $16de,x ; vram address (low, high bytes)
;sta $2116   ; this is the vram address register.
;sep #$20    ;to 8-bit mode
;lda #$01
;sta $420b   ;enable DMA
;rep #$20    ;16-bit mode
;lda $16de,x
;ora #$0100  ;possiblility of making a second copy in vram?
;sta $2116
;sty $4305
;sep #$20
;lda #$01
;sta $420b
;rep #$20
;inx
;inx
;cpx $7c
;bne gfxdma

;phy
;lda $15de,x
;cmp #$8780
;bne pressstart ; will add more conditions checking jumpers
                ; for now, just show...
;ldy $165e,x
;cpy #$008e
;bne pressstart ; will add more conditions checking jumpers
                ; for now, just show...

;lda #$CC00
;sta $4302       ;source register (we are doing a conditional dma to vram)
;lda #$008F
;sta $4304       ;source bank register
;ply
;bra coindone

;pressstart:
;ply
;lda $15de,x
;sta $4302
;lda $165e,x
;sta $4304
;
;coindone:
;jml $80b999

;Check for "Special Keypresses" while in-game
evaluatekeys:
phy
phx
sei
checkp1keys:
lda $006e          ;current P1 keypress (absolute $006E -- D-independent)
and.l !lastp1keys  ;replicate BIT: Z = (current & last) == 0 (no BIT long mode)
bne normalkeys     ;shares bits with last keypress -> treat as held, skip
lda $006e          ;reload current (AND clobbered A)
sta.l !lastp1keys  ;store last keypress in SAFE long-addressed RAM (was "$62")
and #$000f      ;we need the last 8 bits
cmp #$0000      ;is it zero?
beq normalkeys ;not a coin-up, return to normal routine
and #$0001      ;now check to see if the first bit is set (other checks will be here later)
cmp #$0001      ;is coin-up bit set?
beq ekp1coinup ;then branch to p1 coin-up eval routine
bra storenorm  ;store the bit value and continue processing

ekp1coinup:
cmp !lastcredit
beq storenorm
sed
clc
lda $001e72 ;player 1's score...
adc #$0001  ;increment by one (decimal mode)
sta $001e72 ;when this changes, it forces the HUD to update (temporary until i figure out how to trigger this otherwise)
cld

lda #$000e  ;changed sound to one used by all levels. should play consistently.
jsl !playsndsub
clc
lda $7e1d4c ;This is player 1's lives
adc #$0001  ;Coin was inserted... this will have more jumper options later
sta $7e1d4c ;store the incremented entry
;TODO: NEXT SAVE TOTAL ACTIVE CREDITS IN SRAM (to be shared between games)

jml p1coinupentry

storenorm:
sta !lastcredit

normalkeys:
cli
plx
ply
lda $006e
ora $0070
jml $8089b6
