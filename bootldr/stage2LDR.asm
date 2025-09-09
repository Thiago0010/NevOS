; stage2.asm - NASM (16-bit real mode)
; Simple, reliable stage2:
; - mode 0x13 (320x200 256 colors)
; - loads palette, copies splash.img to 0xA000:0
; - shows progress (4.5s), polls Ctrl+T (ASCII 0x14)
; - Ctrl+T => boot menu with Terminal / Safe / Tests / Boot Now
; - after 4.5s or Boot Now => jumps to kernel loader stub

[BITS 16]
[ORG 0x7C00]

%define PROG_TIME_MS 4500        ; 4.5s
%define TICK_MS      100        ; step per update
%define STEPS        (PROG_TIME_MS / TICK_MS)  ; 45

; -------------------------
start:
    cli
    xor ax,ax
    mov ds,ax
    mov es,ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00

    sti

    ; clear screen text
    mov ah,0
    mov al,3
    int 0x10

    ; set video mode 0x13
    mov ax, 0x0013
    int 0x10

    ; load palette
    call load_palette

    ; copy image (splash) into VGA framebuffer at A000:0000
    call draw_splash

    ; show initial percentage (0%)
    call print_percent_label

    ; progress loop - STEPS iterations of TICK_MS ms
    mov cx, STEPS
.progress_loop:
    ; wait ~TICK_MS ms
    call bios_sleep_approx_100ms

    ; increment step counter (we'll compute percentage)
    dec cx
    ; compute step = STEPS - cx
    mov ax, STEPS
    sub ax, cx
    ; ax = step
    push ax
    call print_percent_value
    pop ax

    ; check keyboard: if key available (int 0x16 AH=01) then read and handle
    mov ah, 0x01
    int 0x16
    jz .no_key
    mov ah, 0x00
    int 0x16
    ; AL = ASCII, AH = scan
    cmp al, 0x14        ; Ctrl+T ASCII = 0x14
    jne .no_key
    ; open boot menu
    call boot_menu
.no_key:
    cmp cx, 0
    jne .progress_loop

    ; time finished, boot kernel
    call boot_kernel
    jmp $

; -------------------------
; load_palette: reads included palette (768 bytes), programs VGA DAC
; palette data included below as 'PALETTE_DATA' (incbin)
load_palette:
    pusha
    mov si, palette_data
    ; VGA DAC: write index then R G B values scaled 0-63
    xor dx, dx
    mov dx, 0x03C8
    mov al, 0
    out dx, al          ; start index 0
    mov dx, 0x03C9
    mov cx, 256
.loadpal_loop:
    lodsb               ; R (0..255)
    mov ah, al
    shr al, 2           ; convert 0..255 -> 0..63 (divide by 4)
    out dx, al
    lodsb               ; G
    mov al, ah
    shr al, 2
    out dx, al
    lodsb               ; B
    mov al, ah
    shr al, 2
    out dx, al
    loop .loadpal_loop
    popa
    ret

; -------------------------
; draw_splash: copies included splash_img (320*200 bytes) to 0xA000:0
draw_splash:
    pusha
    cli
    mov ax, 0xA000
    mov es, ax
    xor di, di
    mov si, splash_img
    mov cx, 320*200/2    ; we'll copy words for speed (2 bytes per iter)
.rep_copy:
    lodsw
    stosw
    loop .rep_copy
    sti
    popa
    ret

; -------------------------
; print_percent_label: prints "Booting: " on screen (text via BIOS)
print_percent_label:
    pusha
    mov si, label_booting
    call print_string
    popa
    ret

; print_percent_value: input: AX = step number (0..STEPS)
; computes percent = (step * 100) / STEPS and prints at same line
print_percent_value:
    pusha
    mov bx, AX          ; step
    ; percent = (bx * 100) / STEPS
    mov ax, bx
    mov dx, 0
    mov bx, 100
    mul bx              ; DX:AX = step*100
    ; divide by STEPS
    mov bx, STEPS
    div bx              ; AX = percent
    ; convert AX to decimal string
    mov bx, ax
    mov si, perc_buf+6
    mov byte [si], 0
    dec si
    mov cx, 0
    cmp bx, 100
    jae .write100
    ; two digits or one
    mov dx, 0
    mov ax, bx
    mov bx, 10
    div bx              ; ax = tens; dx = ones
    add al, '0'
    mov [si], al
    dec si
    add dl, '0'
    mov [si+1], dl
    jmp .doneconv
.write100:
    mov byte [si-2], '1'
    mov byte [si-1], '0'
    mov byte [si], '0'
    lea si, [si-2]
.doneconv:
    ; now print percent and '%' at current cursor using BIOS teletype
    mov ah, 0x0E
    mov bx, si
.print_loop_val:
    lodsb
    or al, al
    jz .endprint_val
    int 0x10
    jmp .print_loop_val
.endprint_val:
    popa
    ret

; -------------------------
; bios_sleep_approx_100ms: uses int 0x15 AH=0x86 (bios wait in microseconds) if supported,
; fallback to simple busy loop.
bios_sleep_approx_100ms:
    pusha
    mov ah, 0x86
    mov cx, 0
    mov dx, 100000      ; 100000 us = 100ms
    int 0x15
    jc .busy_fallback
    popa
    ret
.busy_fallback:
    ; busy loop approx (tunable)
    mov cx, 0xFFFF
.bloop:
    nop
    loop bloop
    popa
    ret

; -------------------------
; boot_menu: simple text menu
boot_menu:
    pusha
    ; clear screen (scroll)
    mov ah, 0x06
    mov al, 0
    mov bh, 0x07
    mov cx, 0
    mov dx, 184
    int 0x10

    mov si, menu_header
    call print_string
.menu_wait:
    mov si, menu_options
    call print_string

    ; read key
    mov ah, 0
    int 0x16
    cmp al, '1'
    je .menu_terminal
    cmp al, '2'
    je .menu_safe
    cmp al, '3'
    je .menu_tests
    cmp al, '4'
    je .menu_bootnow
    jmp .menu_wait

.menu_terminal:
    call tiny_terminal
    jmp boot_menu_end
.menu_safe:
    ; set a flag in memory (word at 0x7C00+0x0200)
    mov word [boot_flags], 1
    ; boot now
    call boot_kernel
    jmp $
.menu_tests:
    call run_tests
    jmp boot_menu_end
.menu_bootnow:
    call boot_kernel
    jmp $

boot_menu_end:
    popa
    ret

; -------------------------
; tiny_terminal - very small REPL with 'ls', 'reboot', 'boot'
tiny_terminal:
    pusha
    mov si, term_welcome
    call print_string

.termloop:
    mov si, term_prompt
    call print_string
    ; read line into buffer at term_input
    call read_line
    ; compare strings (very simple)
    mov si, term_input
    call strcmp_str, cmd_ls
    cmp al, 0
    je .do_ls
    mov si, term_input
    call strcmp_str, cmd_reboot
    cmp al, 0
    je .do_reboot
    mov si, term_input
    call strcmp_str, cmd_boot
    cmp al, 0
    je .do_boot
    ; unknown
    mov si, unknown_cmd
    call print_string
    jmp .termloop

.do_ls:
    mov si, ls_stub
    call print_string
    jmp .termloop

.do_reboot:
    ; BIOS warm reboot via 0xFFFF:0
    cli
    mov ax, 0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    mov si, 0
    xor ax, ax
    mov es, ax
    mov es:[0x472], si
    mov al, 0
    out 0x64, al
    jmp $

.do_boot:
    ; boot kernel
    call boot_kernel
    jmp $

; -------------------------
; run_tests - simple stubs
run_tests:
    pusha
    mov si, test_running
    call print_string
    ; small delay
    call bios_sleep_approx_100ms
    mov si, test_done
    call print_string
    popa
    ret

; -------------------------
; boot_kernel - stub: in real use replace with INT13 loading kernel etc.
boot_kernel:
    pusha
    mov si, booting_kernel
    call print_string
    ; For now just hang (or chain to next stage)
    ; TODO: implement reading kernel from disk and far jump to it
    popa
    ret

; -------------------------
; small helper routines: printing strings, read_line, strcmp simple
print_string:
    pusha
.nextchar:
    lodsb
    or al, al
    jz .done_ps
    mov ah, 0x0E
    int 0x10
    jmp .nextchar
.done_ps:
    popa
    ret

; read_line: reads chars until Enter (CR). stores at term_input (zero-terminated)
; Very simple echo input using int 0x16
read_line:
    pusha
    mov di, term_input
.readloop:
    mov ah, 0
    int 0x16
    cmp al, 0x0D
    je .done_read
    ; echo
    mov ah, 0x0E
    int 0x10
    stosb
    jmp .readloop
.done_read:
    mov byte [di], 0
    popa
    ret

; strcmp_str: compares string at SI with string passed as operand (pointer in follow-up word)
; returns AL=0 if equal, else non-zero. (very small helper - caller sets DI to pointer of pattern)
; We'll implement small usage patterns via manual compares later - keep minimal.
strcmp_str:
    pusha
    mov di, [rel strcmp_arg]
.cmploop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .neq
    or al, al
    jz .eq
    inc si
    inc di
    jmp .cmploop
.neq:
    mov al, 1
    jmp .done_cmp
.eq:
    mov al, 0
.done_cmp:
    popa
    ret
strcmp_arg dw 0

; -------------------------
; data includes
menu_header db "=== Boot Menu ===",13,10,0
menu_options db "1) Terminal  2) Safe Mode  3) Tests  4) Boot Now",13,10,0
label_booting db "Booting: ",0
perc_buf times 8 db 0

term_welcome db "Tiny shell. commands: ls, reboot, boot",13,10,0
term_prompt db "shell> ",0
term_input times 64 db 0
cmd_ls db "ls",0
cmd_reboot db "reboot",0
cmd_boot db "boot",0
ls_stub db "files: (no filesystem implemented)",13,10,0
unknown_cmd db "Unknown command",13,10,0

test_running db "Running tests...",13,10,0
test_done db "Tests done",13,10,0
booting_kernel db "Jumping to kernel...",13,10,0

boot_flags dw 0

; -------------------------
; Binary-included data: splash image and palette
; These files must exist in build folder: splash.img (320*200 bytes) and splash.pal (768 bytes)
section .data
splash_img:
    incbin "splash.img"
palette_data:
    incbin "splash.pal"

; -------------------------
times 510-($-$$) db 0
dw 0xAA55
