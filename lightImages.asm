%include    "sys-equal.asm"
%include    "in_out.asm"

section .data
    editedDir       db "edited_photo", 0
    currentDir      db ".", 0
    preDir          db "..", 0
    IDD             dq 0
    FDS             dq 0
    FDD             dq 0
    fileName        dq 0
    n               db 0
    flag            db 0
    sys_chdir       equ 0x50
    sys_mkdir       equ 0x53
    sys_getdents64  equ 0xd9
    bufferSize      equ 4096
section .bss
    dirPath     resb 1024
    dirBuffer   resb bufferSize * bufferSize
    buffer      resb bufferSize
    pixelP      resb 4
    width       resb 4
    ow          resb 4
    height      resb 4
    header      resb 4

section .text
    global _start

readStr:
    push    r8
    push    rax
    mov     r8, dirPath
getCharAgain:
    call    getc
    cmp     al, NL
    je      getCharEnd
    mov     [r8], al
    inc     r8
    jmp     getCharAgain
getCharEnd:
    mov     byte[r8], 0
    pop     rax
    pop     r8
    ret

addOrSub:
    cmp     byte[flag], 1
    je      IsSub
    paddusb xmm0, xmm2
    ret
IsSub:
    psubusb xmm0,xmm2
    ret

addbuffer:
    push    r15
    push    rax
    xor     r15, r15
    mov     rax, buffer
    vpbroadcastb    xmm2, byte[n]
addbufferL1:
    cmp     r15, 256
    je      addbufferL1C

    movq    xmm0, [rax]
    movq    xmm1, [rax + 8]
    pslldq  xmm1, 8
    paddb   xmm0, xmm1

    call    addOrSub

    movq    [rax], xmm0
    psrldq  xmm0, 8
    movq    [rax + 8], xmm0

    add     rax, 16
    inc     r15
    jmp     addbufferL1
addbufferL1C:
    pop     rax
    pop     r15
    ret

edit:
    ;open s
    mov     rax, sys_open
    mov     rdi, [fileName]
    mov     rsi, O_RDWR
    syscall
    mov     [FDS], rax
    ;is bmp
    mov     rax, sys_read
    mov     rdi, [FDS]
    mov     rsi, buffer
    mov     rdx, 2
    syscall

    cmp     byte[buffer], 66
    jne     isNotBmp
    cmp     byte[buffer + 1], 77
    jne     isNotBmp

    mov     rax, sys_chdir
    mov     rdi, editedDir
    syscall
    ;open d
    mov     rax, sys_create
    mov     rdi, [fileName]
    mov     rsi, sys_IRUSR | sys_IWUSR
    syscall
    mov     [FDD], rax

    ;skip header
    mov     rax, sys_lseek
    mov     rdi, [FDS]
    mov     rsi, 10
    mov     rdx, 0
    syscall
    ;where is pixels
    mov     rax, sys_read
    mov     rdi, [FDS]
    mov     rsi, pixelP
    mov     rdx, 4
    syscall
    ;header size
    mov     rax, sys_read
    mov     rdi, [FDS]
    mov     rsi, header
    mov     rdx, 4
    syscall

    mov     r15, 2
    mov     r14, 4
    cmp     dword[header], 12
    cmovne  r15, r14

    ;width
    mov     rax, sys_read
    mov     rdi, [FDS]
    mov     rsi, width
    mov     rdx, r15
    syscall

    ;cal ow
    mov     r14, 4
    mov     r13, 3
    xor     rax, rax
    mov     eax, dword[width]
    mul     r13
    mov     [width], eax
    xor     rdx, rdx
    div     r14
    sub     r14, rdx
    xor     rax, rax
    mov     eax, r14d
    mov     r14, 4
    xor     rdx, rdx
    div     r14
    mov     dword[ow], edx
    ;height
    mov     rax, sys_read
    mov     rdi, [FDS]
    mov     rsi, height
    mov     rdx, r15
    syscall
    ;reset file pointer
    mov     rax, sys_lseek
    mov     rdi, [FDS]
    mov     rsi, 0
    mov     rdx, 0
    syscall

    ;befor pixels
    mov     rax, sys_read
    mov     rdi, [FDS]
    mov     rsi, buffer
    xor     rdx, rdx
    mov     edx, [pixelP]
    syscall
    mov     r15, rax
    mov     rax, sys_write
    mov     rdi, [FDD]
    mov     rsi, buffer
    mov     rdx, r15
    syscall


    mov     r15d, 0
editL1:
    cmp     r15d, dword[height]
    je      editedL1C
    mov     rax, sys_read
    mov     rdi, [FDS]
    mov     rsi, buffer
    xor     rdx, rdx
    mov     edx, [width]
    syscall
    call    addbuffer
    mov     rax, sys_write
    mov     rdi, [FDD]
    mov     rsi, buffer
    xor     rdx, rdx
    mov     edx, [width] 
    syscall
    ;4
    mov     rax, sys_read
    mov     rdi, [FDS]
    mov     rsi, buffer
    xor     rdx, rdx
    mov     edx, [ow]
    syscall
    mov     rax, sys_write
    mov     rdi, [FDD]
    mov     rsi, buffer
    xor     rdx, rdx
    mov     edx, [ow] 
    syscall

    inc     r15d

    jmp     editL1
editedL1C:

editL2:
    mov     rax, sys_read
    mov     rdi, [FDS]
    mov     rsi, buffer
    mov     rdx, bufferSize
    syscall
    mov     r15, rax
    cmp     rax, 0
    je      editedL2C
    mov     rax, sys_write
    mov     rdi, [FDD]
    mov     rsi, buffer
    mov     rdx, r15
    syscall
    jmp     editL2
editedL2C:
    mov     rax, sys_close
    mov     rdi, [FDS]
    syscall

    mov     rax, sys_close
    mov     rdi, [FDD]
    syscall


    mov     rax, sys_chdir
    mov     rdi, preDir
    syscall

    ret

isNotBmp:
    mov     rax, sys_close
    mov     rdi, [FDS]
    syscall
    ret

normalizeRax:
    cmp     rax, 0
    jnl     normalizeRaxC
    neg     rax
    mov     byte[flag], 1
normalizeRaxC:
    cmp     rax, 255
    jl      normalizeRaxCEnd
    mov     rax, 255
normalizeRaxCEnd:
    ret
_start:
    call    readStr
    call    readNum

    call    normalizeRax
    mov     [n], al


    mov     rax, sys_chdir
    mov     rdi, dirPath
    syscall

    mov     rax, sys_mkdir
    mov     rdi, editedDir
    mov     rsi, 0q777
    syscall

    mov     rax, sys_open
    mov     rdi, currentDir
    mov     rsi, O_RDONLY
    mov     rdx, 0q777
    syscall
    mov     [IDD], rax

readFileNames:
    mov     rax, sys_getdents64
    mov     rdi, [IDD]
    mov     rsi, dirBuffer
    mov     rdx, 100
    syscall
    cmp     rax, 0
    je      readFileNamesE

    mov     r8, dirBuffer
    add     r8, rax
    mov     rcx, dirBuffer
    xor     r9, r9
readFileNamesL1:
    add     rcx, r9
    cmp     rcx, r8
    jge     readFileNamesL1E
    xor     r9, r9
    mov     r9w, [rcx + 16]
    xor     r10, r10
    mov     r10b, [rcx + 18]
    cmp     r10, 8
    je      isFile
    jmp     readFileNamesL1
readFileNamesL1E:
    jmp     readFileNames
readFileNamesE:
    mov     rax, sys_close
    mov     rdi, [IDD]
    syscall
exit:
    mov     rax, sys_exit
    xor     rdi, rdi
    syscall


isFile:
    mov     [fileName], rcx
    add     qword[fileName], 19
    ; mov     rsi, [fileName]
    ; call    printString
    ; call    newLine
    push    r8
    push    r9
    push    r10
    push    rcx
    call    edit
    pop     rcx
    pop     r10
    pop     r9
    pop     r8
    jmp     readFileNames