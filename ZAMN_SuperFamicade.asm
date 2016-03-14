; Purpose: Zombies ate my Neighbors Modified HUD writer, Blood Hack, High Score Save
; Date: 09,10,12 March 2016
; Author: DackR
lorom

;variables...
!p2StartDrawn = $7e1d40 
!aVar = $7e1d42
!demoSceneChecker = $7e1d44 
!playerIndex = $7e1d46
!playerLives = $7e1d4c
!mapType = $7e1d48
!tileDefLoc = $7e5efa

!lifeTable = $ff50
!lifeTiles = $ff70
!livesTileMap = $ffa0
!demoTileMap = $ffb0

;Indicate ROM + RAM + SRAM
org $ffd6
db $02

;2kb SRAM
org $ffd8
db $01

org $96F121
incbin .\bin\0xB7121.bin

;life number table
org $ff50
db $00,$00,$01,$00,$02,$00,$03,$00,$04,$00,$05,$00,$06,$00,$07,$00
db $08,$00,$09,$00,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; tiles corresponding to life numbers
;org $ff70
db $3C,$07,$00,$00,$3C,$08,$00,$00,$3C,$09,$00,$00,$3C,$0A,$00,$00
db $3C,$0B,$00,$00,$3C,$0C,$00,$00,$3C,$0D,$00,$00,$3C,$0E,$00,$00
db $3C,$0F,$00,$00,$3C,$10,$00,$00,$3C,$10,$3C,$8E,$3C,$10,$3C,$8E
; number of tiles, and tile defs for LIVES:
;org $FFA0 
db $0c,$00,$9B,$3C,$98,$3C,$A5,$3C,$94,$3C,$A2,$3C,$8F,$3C,$00,$00
; tile definition for DEMO MODE
;org $FFB0 
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
org $9E9026
db $15,$00,$13,$00,$0F,$00,$0C,$00,$09,$00

;Adding some code to the DMA transfer...
org $80c34a ; 44 bytes long (2C)
jml @dmahud
rep 40 : nop ;TODO: need to add more nops since i've skipped the next transfer

; Hijacking death (lives--) code for hud generation
org $80cec5
jml $82F9A0
nop

; Hijack beginning of level...
org $80866A
jml $82F980

;hijacking high score table build...
org $82bb13
jml @makescoretable
rep 8 : nop

;hijacking score save!
org $82bd2f
jml @xferscore
rep 2 : nop

org $82F980
lda #$0001  ;entry point for beginning of level
sta !mapType
lda #$0000
sta !p2StartDrawn
jmp @makelifemap

org $82F9A0
lda #$0000  ; entry point for death
sta !mapType
jmp @makelifemap

; This section actually generates the lives counter
makelifemap:
txa ;transfer the player index...
sta !playerIndex ; store the player currently being handled (0,2) [P1,P2]
cmp #$0002
bne @p1map
beq @p2map
p1map:
ldx #$0000
jmp @anymap
p2map:
ldx #$0020
jmp @anymap
anymap:
ldy #$0002 ; start reading past the number

repeatmap: ; copy the Lives: tiles to RAM
lda !livesTileMap, y 
jsr @store
;tay ;temporarily copy a->y
cpy !livesTileMap ;are we at the last tile?
bcs @numgen
rep 2 : iny
jmp @repeatmap

;generate map for lives left # here...
numgen:
txy
ldx !playerIndex       ; use current player index
lda #$0000 
cmp !playerLives, x		 ; **this is the game variable for # of lives left
beq @foundzero
sta !aVar
incloop:
lda !aVar
inc a 
cmp !playerLives, x		  ; **this is the game variable for # of lives left
beq @foundnum
sta !aVar
lda #$000a
cmp !playerLives, x		  ; **this is the game variable for # of lives left
bpl @incloop            ; number of lives less than 9 (since we haven't -- yet)
bmi @foundplus          ; number of lives is greater than 9

endmapgen:
lda #$0000
cmp !mapType		  ; **this varaible contains 0=death, 1=lvl start
bne @levelstart   ; if this isnt generated from a death, then branch w/o --
                  ; otherwise... its a death.
isdeath:
ldx !playerIndex
sep #$20
lda !playerLives,x		; **this is the game variable for # of lives left
dec a			            ; --
sta !playerLives,x		; **this is the game variable for # of lives left
rep #$30
bmi @isneg
jml $80ceca ;Return back to the main routine

foundzero:
jmp @gameover

isneg:
jml $80ced5 ; this triggers player game over

drawp1tiles:
ldx #$0000
jml @makelifemap

drawp2tiles:
ldx #$0002
lda #$0001
sta !p2StartDrawn
jml @makelifemap

levelstart:
ldx !playerIndex
lda !playerLives,x
sta !demoSceneChecker ; this is so we can tell if the lives dec without death
;check to see if we need to draw some MOAR!
lda !playerIndex
cmp #$0002
beq @drawp1tiles ;still need to do P1, yo!

;this is a check to see if p2 hud update is still needed
;check if p1 has lives...
lda !playerIndex
cmp #$0000
bne @alldonestart
lda !playerLives,x
cmp #$0000
bne @alldonestart
lda !p2StartDrawn
cmp #$0000
beq @drawp2tiles ;map up player two

alldonestart:
jml $80c2da ;back to level start

foundnum:
tyx
jsr @numstore
jmp @endmapgen

foundplus:	; Number of lives is greater than 9... kinda lazy
tyx
jsr @numstoreplus
jmp @endmapgen

store:	; store the tile definition in WRAM
sta !tileDefLoc,x
inx
inx
rts

numstore:	; pretty much like "store", but handles numbers
dec a
dec a
adc #$3c07	; adding the value of the tile representing "0"
clc			    ; clear carry because... we dont want anything extra next adc
adc !mapType ; add one if we are starting the level!!
cmp #$3c11	; ****this might need to be modified...
bcs @numstoreplus ; if we have more than 9 now.. do 9+ 
sta !tileDefLoc,x
inx
inx
lda #$0000
sta !tileDefLoc,x
inx
inx
rts

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
lda !playerIndex
cmp #$0002
bne @p1go
beq @p2go
p1go:
ldx #$0000
bra @allgo
p2go:
ldx #$0020
allgo:
ldy #$0007 ;number of tiles to clear

clearstuff:
lda #$0000
jsr @store
dey
cpy #$0000
bpl @clearstuff

jmp @endmapgen


makescoretable:
lda $700010
cmp #$0666 ;check to see if the table is already written
beq @writewram

lda #$0000
sta $700000

ldx #$0000
ldy #$0001
lda #$07fe
mvn $7070 ;clear sram

ldx #$bb2e
ldy #$2064
lda #$00BC ;instead of just $95, transfer $BC
mvn $827e

ldx #$2064
ldy #$0020
lda #$00BC
mvn $7e70

lda #$0666
sta $700010 ;table now exists

writewram:
ldx #$0020
ldy #$2064
lda #$00BC
mvn $707e

jml $82bb2b ;$82bb1f ; jump back to main init routine

lifediff:
lda #$0003
sta !mapType ;just write this so we dont waste time writing tilemap again
ldx #$0000
ldy #$0002 ; start reading past the number
repeatdemo: 
; copy the DEMO MODE tiles to RAM
lda !demoTileMap, y 
jsr @store
;tay ;temporarily copy a->y
cpy !demoTileMap ;are we at the last tile?
bcs @startdma
rep 2 : iny
jmp @repeatdemo

dmahud:
phx ;cause I dont know if it's in use...
phy ;cause I dont know if it's in use...
lda !playerIndex
cmp #$0000
bne @startdma
lda !mapType
cmp #$0001
bne @startdma
lda !playerLives
cmp !demoSceneChecker
bne @lifediff
;playerindex=0
;if maptype=1 (scene just loaded)
;check if lives match last known if there were no deaths
;if maptype is 1 and the lives dont match == demo

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
			      ; (Not sure why, but this Transfer actually writes to $C822...)

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

jml $80c376
;END OF HUD WRITER CODE

;COPY SCORE TO SRAM!
xferscore:
mvn $007e ;this is where I hijacked it

;save it to SRAM!
ldx #$2064
ldy #$0020
lda #$00BC
mvn $7e70

;same as old routine exit
plb
plb
rts

;next hijack the high score save...so it saves in wram and sram
