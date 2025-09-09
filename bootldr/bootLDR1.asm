

BITS 16
ORG 0x7C00  ; Bootloader loaded at 0x7C00

; Constants
SECTOR_SIZE EQU 512
STAGE2_START_SECTOR EQU 2  ; Stage 2 starts at sector 2 (sector 1 is bootloader)
STAGE2_SECTORS EQU 19      ; Number of sectors to load for Stage 2 (adjust as needed, max to fit in memory)
STAGE2_LOAD_ADDR EQU 0x7E00 ; Load address for Stage 2 (right after bootloader)

; Bootloader entry point
start:
    cli                ; Disable interrupts
    xor ax, ax         ; Zero AX
    mov ds, ax         ; Set DS to 0
    mov es, ax         ; Set ES to 0
    mov ss, ax         ; Set SS to 0
    mov sp, 0x7C00     ; Set stack pointer below bootloader
    sti                ; Enable interrupts

    ; Reset disk system
    mov ah, 0          ; Reset disk function
    mov dl, 0x80       ; Drive number (0x00 for floppy, 0x80 for first HDD)
    int 0x13           ; Call BIOS interrupt
    jc disk_error      ; Jump if carry flag set (error)

    ; Load Stage 2 using INT 13h AH=02h (Read Sectors)
    mov ah, 0x02       ; Read sectors function
    mov al, STAGE2_SECTORS ; Number of sectors to read
    mov ch, 0          ; Cylinder 0
    mov cl, STAGE2_START_SECTOR ; Sector to start reading from
    mov dh, 0          ; Head 0
    mov bx, STAGE2_LOAD_ADDR ; ES:BX = load address (ES=0 already)
    int 0x13           ; Call BIOS interrupt
    jc disk_error      ; Error if carry set
    cmp al, STAGE2_SECTORS ; Check if all sectors were read
    jne disk_error     ; If not, error

    ; Jump to Stage 2
    jmp 0x0000:STAGE2_LOAD_ADDR

; Error handling
disk_error:
    mov si, error_msg  ; Load error message address
print_loop:
    lodsb              ; Load byte from SI into AL
    or al, al          ; Check if end of string
    jz hang            ; If zero, hang
    mov ah, 0x0E       ; Teletype output
    int 0x10           ; BIOS video interrupt
    jmp print_loop     ; Next character

hang:
    cli                ; Disable interrupts
    hlt                ; Halt CPU
    jmp hang           ; Infinite loop

; Data
error_msg db 'Disk error! Press any key to reboot...', 0

; Fill to 510 bytes and add boot signature
times 510 - ($ - $$) db 0
dw 0xAA55  ; Boot signature