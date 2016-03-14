
;ZAMN Joypad reading routine before game starts - Konami Screen

org $8081b5 
lda $4212   ; PPU Status register - Check Auto-Joypad 
lsr a       ; shift out the first bit (auto-joypad status)
bcs $81b5   ; branch loop if carry is set (auto-joypad not set) 
;Auto-Joypad set
rep #$30    ; 16-bit mode
lda $4218   ; Load P1 Controller data 
sta $6e     ; store it at address $00006e
xba         ; exchange high-low bytes
and #$000f  ; appears to be checking directional buttons
tax         ; x to a                         (na,r-,l-,na,d-,rd,ld,na,u-,ru,lu,na,na,na,na,na)
lda $81f9,x ; $8081f9 - possible values: 0-f (00,06,0e,00,0a,08,0c,00,02,04,10,00,00,00,00,00,40) 
and #$00ff  ; kill the high byte             (00,01,02,03,04,05,06,07,08,09,0A,0B,0C,0D,0E,0F)
sta $72     ; store it here... $000072--- holds the direction(s) being pressed
;Now the same for P2!
lda $421a   ; Load P2 Data...
sta $70     ; do the same stuff... but store at different memory addresses
xba        
and #$000f 
tax        
lda $81f9,x
and #$00ff
sta $74   
jsr $843d   ; Not sure what this subroutine does...
lda $0e     ; seems unrelated
beq $8474   ; maybe a counter that transitions the screen??...
rts    