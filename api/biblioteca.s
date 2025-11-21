@=============================================================================
@ Arquivo: fpga_control.s
@ Descrição: Biblioteca em Assembly ARM para comunicação com FPGA via mapeamento
@            de memória. Permite enviar imagens e comandos de processamento
@            (zoom in/out) para um coprocessador de imagem em hardware.
@
@ Plataforma: ARM Linux (DE1-SoC / Cyclone V)
@=============================================================================

.section .text

@-----------------------------------------------------------------------------
@ Declaração de Símbolos Globais (exportados para uso em C ou outros módulos)
@-----------------------------------------------------------------------------
.global mapear_enderecos
.type mapear_enderecos, %function

.global enviar_imagem_fpga
.type enviar_imagem_fpga, %function

.global replicacao_pixel
.type replicacao_pixel, %function

.global vizinho_mais_proximo
.type vizinho_mais_proximo, %function

.global decimacao
.type decimacao, %function

.global media_de_blocos
.type media_de_blocos, %function

.global fechar_enderecos
.type fechar_enderecos, %function


@=============================================================================
@ Função: mapear_enderecos
@ Descrição: Abre o dispositivo /dev/mem e mapeia a região de memória da FPGA
@            para acesso direto aos registradores de hardware.
@
@ Parâmetros: Nenhum
@ Retorno: Nenhum (ponteiros armazenados em variáveis globais)
@
@ Syscalls utilizadas:
@   - open (5): Abre /dev/mem
@   - mmap2 (192): Mapeia memória física para virtual
@
@ Endereços mapeados:
@   - 0xFF200000: Base dos periféricos lightweight HPS-to-FPGA
@   - ponteiro_instrucoes: Endereço para envio de comandos à FPGA
@=============================================================================
mapear_enderecos:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #36
    str     r0, [sp, #0]
    str     r1, [sp, #4]
    str     r2, [sp, #8]
    str     r3, [sp, #12]
    str     r4, [sp, #16]
    str     r5, [sp, #20]
    str     r6, [sp, #24]
    str     r7, [sp, #28]
    str     lr, [sp, #32]

    @ --- Syscall open("/dev/mem", O_RDWR) ---
    ldr     r0, =dev_mem            @ r0 = caminho do dispositivo
    mov     r1, #2                  @ r1 = O_RDWR (leitura e escrita)
    mov     r2, #0                  @ r2 = modo (não usado)
    mov     r7, #5                  @ r7 = syscall number (open)
    svc     0                       @ executa syscall

    mov     r4, r0                  @ r4 = file descriptor retornado

    @ Armazena o file descriptor para uso posterior
    ldr     r0, =ponteiro_fd
    str     r4, [r0]

    @ --- Syscall mmap2(NULL, 0x5000, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0xFF200) ---
    mov     r0, #0                  @ r0 = addr (NULL = kernel escolhe)
    ldr     r1, =0x00005000         @ r1 = length (20KB)
    mov     r2, #3                  @ r2 = prot (PROT_READ | PROT_WRITE)
    mov     r3, #1                  @ r3 = flags (MAP_SHARED)
    mov     r4, r4                  @ r4 = fd (file descriptor)
    ldr     r5, =0xFF200            @ r5 = offset/4096 (0xFF200000 >> 12)
    mov     r7, #192                @ r7 = syscall number (mmap2)
    svc     0                       @ executa syscall

    @ Calcula e armazena o ponteiro para registrador de instruções
    mov     r5, r0                  @ r5 = endereço base mapeado
    ldr     r6, =0x00000000         @ offset do registrador de instruções
    add     r6, r5, r6              @ r6 = endereço final

    ldr     r0, =ponteiro_instrucoes
    str     r6, [r0]

    mov     r4, r6

    @ Calcula ponteiro adicional (offset 0x10) - reservado para uso futuro
    ldr     r6, =0x00000010
    add     r6, r5, r6

    @ --- Restaurar registradores da pilha ---
    ldr     r0, [sp, #0]
    ldr     r1, [sp, #4]
    ldr     r2, [sp, #8]
    ldr     r3, [sp, #12]
    ldr     r4, [sp, #16]
    ldr     r5, [sp, #20]
    ldr     r6, [sp, #24]
    ldr     r7, [sp, #28]
    ldr     lr, [sp, #32]
    add     sp, sp, #36

    bx      lr


@=============================================================================
@ Função: abrir_imagem (interna/privada)
@ Descrição: Abre o arquivo de imagem PGM e carrega os dados para o buffer.
@            Ignora o cabeçalho PGM (15 bytes) e lê os pixels raw.
@
@ Parâmetros: Nenhum
@ Retorno: r0 = ponteiro para o buffer de imagem (input_buffer)
@
@ Formato esperado: PGM binário (P5), 320x240 pixels, 8 bits por pixel
@ Tamanho dos dados: 76800 bytes (320 * 240)
@=============================================================================
abrir_imagem:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #24
    str     r4, [sp, #0]
    str     r7, [sp, #4]
    str     lr, [sp, #8]
    str     r1, [sp, #12]
    str     r2, [sp, #16]
    str     r3, [sp, #20]

    @ --- Syscall open("imagem.pgm", O_RDONLY) ---
    mov     r1, #0                  @ r1 = O_RDONLY
    mov     r2, #0                  @ r2 = modo (não usado)
    mov     r7, #5                  @ r7 = syscall number (open)
    svc     0                       @ executa syscall

    mov     r4, r0                  @ r4 = file descriptor

    @ Armazena o file descriptor da imagem
    ldr     r1, =ponteiro_fd_imagem
    str     r0, [r1]

    @ --- Lê e descarta o cabeçalho PGM (15 bytes) ---
    mov     r0, r4                  @ r0 = fd
    ldr     r1, =input_buffer       @ r1 = buffer temporário
    mov     r2, #15                 @ r2 = tamanho do cabeçalho
    mov     r7, #3                  @ r7 = syscall number (read)
    svc     0                       @ executa syscall

    @ --- Lê os dados da imagem (76800 bytes) ---
    mov     r0, r4                  @ r0 = fd
    ldr     r1, =input_buffer       @ r1 = buffer de destino
    mov     r2, #76800              @ r2 = 320 * 240 pixels
    mov     r7, #3                  @ r7 = syscall number (read)
    svc     0                       @ executa syscall

    @ Retorna ponteiro para o buffer
    ldr     r0, =input_buffer

    @ --- Restaurar registradores da pilha ---
    ldr     r4, [sp, #0]
    ldr     r7, [sp, #4]
    ldr     lr, [sp, #8]
    ldr     r1, [sp, #12]
    ldr     r2, [sp, #16]
    ldr     r3, [sp, #20]
    add     sp, sp, #24

    bx      lr


@=============================================================================
@ Função: enviar_imagem_fpga
@ Descrição: Carrega uma imagem PGM do disco e envia pixel a pixel para a FPGA.
@            Cada pixel é empacotado em uma instrução de 32 bits com:
@            - Bits [31:29]: Opcode (0b111 = escrita de pixel)
@            - Bits [28:12]: Endereço do pixel (0 a 76799)
@            - Bits [11:4]: Valor do pixel (0 a 255)
@
@ Parâmetros: r0 = ponteiro para o buffer de imagem
@ Retorno: Nenhum
@
@ Formato da instrução de escrita:
@   [31:29] = 111 (opcode)
@   [28:12] = endereço (17 bits)
@   [11:4]  = valor do pixel (8 bits)
@   [3:0]   = reservado
@=============================================================================
enviar_imagem_fpga:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #36
    str     r0, [sp, #0]
    str     r1, [sp, #4]
    str     r2, [sp, #8]
    str     r3, [sp, #12]
    str     r4, [sp, #16]
    str     r5, [sp, #20]
    str     r6, [sp, #24]
    str     r7, [sp, #28]
    str     lr, [sp, #32]

    @ Abre e carrega a imagem para o buffer
    bl      abrir_imagem

    mov     r6, r0                  @ r6 = ponteiro para dados da imagem

    @ Carrega ponteiro de instruções da FPGA
    ldr     r4, =ponteiro_instrucoes
    ldr     r4, [r4]

    mov     r3, #0                  @ r3 = contador de pixels (0 a 76799)

enviar_proximo_pixel:
    @ Verifica se todos os pixels foram enviados
    cmp     r3, #76800
    beq     fim_envio_imagem

    @ Carrega próximo pixel e incrementa ponteiro
    ldrb    r2, [r6], #1            @ r2 = valor do pixel, r6++

    @ --- Monta instrução de 32 bits ---
    @ Opcode: 0b111 nos bits [31:29]
    mov     r0, #0b111
    lsl     r0, r0, #29

    @ Endereço do pixel nos bits [28:12]
    mov     r1, r3
    lsl     r1, r1, #12

    @ Valor do pixel nos bits [11:4]
    lsl     r2, r2, #4

    @ Combina todos os campos
    orr     r0, r0, r1
    orr     r0, r0, r2

    @ Envia instrução para a FPGA
    str     r0, [r4]

    @ Incrementa contador
    add     r3, r3, #1

    b       enviar_proximo_pixel

fim_envio_imagem:
    @ Envia instrução NOP (0x00000000) para finalizar
    mov     r0, #0
    str     r0, [r4]

    @ --- Restaurar registradores da pilha ---
    ldr     r0, [sp, #0]
    ldr     r1, [sp, #4]
    ldr     r2, [sp, #8]
    ldr     r3, [sp, #12]
    ldr     r4, [sp, #16]
    ldr     r5, [sp, #20]
    ldr     r6, [sp, #24]
    ldr     r7, [sp, #28]
    ldr     lr, [sp, #32]
    add     sp, sp, #36

    bx      lr



@=============================================================================
@ Função: replicacao_pixel
@ Descrição: Envia comando de zoom in usando o algoritmo de replicação de pixel.
@  
@
@ Parâmetros: Nenhum
@ Retorno: Nenhum
@
@ Comando enviado: 0x80000000
@   - Bits [31:29] = 100 (opcode replicação)
@=============================================================================
replicacao_pixel:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #12
    str     r0, [sp, #0]
    str     r1, [sp, #4]
    str     r2, [sp, #8]

    @ Carrega comando de replicação de pixel
    ldr     r0, =0x80000000

    @ Obtém ponteiro de instruções
    ldr     r1, =ponteiro_instrucoes
    ldr     r1, [r1]

    @ Envia comando para a FPGA
    str     r0, [r1]

    @ --- Restaurar registradores da pilha ---
    ldr     r0, [sp, #0]
    ldr     r1, [sp, #4]
    ldr     r2, [sp, #8]
    add     sp, sp, #12

    bx      lr


@=============================================================================
@ Função: vizinho_mais_proximo
@ Descrição: Envia comando de zoom in usando interpolação por vizinho mais
@            próximo.
@ Parâmetros: Nenhum
@ Retorno: Nenhum
@
@ Comando enviado: 0x60000000
@   - Bits [31:29] = 011 (opcode vizinho mais próximo - zoom in)
@=============================================================================
vizinho_mais_proximo:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #12
    str     r0, [sp, #0]
    str     r1, [sp, #4]
    str     r2, [sp, #8]

    @ Carrega comando de vizinho mais próximo
    ldr     r0, =0x60000000

    @ Obtém ponteiro de instruções
    ldr     r1, =ponteiro_instrucoes
    ldr     r1, [r1]

    @ Envia comando para a FPGA
    str     r0, [r1]

    @ --- Restaurar registradores da pilha ---
    ldr     r0, [sp, #0]
    ldr     r1, [sp, #4]
    ldr     r2, [sp, #8]
    add     sp, sp, #12

    bx      lr


@=============================================================================
@ Função: decimacao
@ Descrição: Envia comando de zoom out usando decimação 
@ Parâmetros: Nenhum
@ Retorno: Nenhum
@
@ Comando enviado: 0xA0000000
@   - Bits [31:29] = 101 (opcode decimação - zoom out)
@=============================================================================
decimacao:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #16
    str     r0, [sp, #0]
    str     r1, [sp, #4]
    str     r2, [sp, #8]
    str     lr, [sp, #12]

    @ Carrega comando de decimação
    ldr     r0, =0xA0000000

    @ Obtém ponteiro de instruções
    ldr     r1, =ponteiro_instrucoes
    ldr     r1, [r1]

    @ Envia comando para a FPGA
    str     r0, [r1]

    @ --- Restaurar registradores da pilha ---
    ldr     r0, [sp, #0]
    ldr     r1, [sp, #4]
    ldr     r2, [sp, #8]
    ldr     lr, [sp, #12]
    add     sp, sp, #16

    bx      lr


@=============================================================================
@ Função: media_de_blocos
@ Descrição: Envia comando de zoom out usando média de blocos.
@            
@ Parâmetros: Nenhum
@ Retorno: Nenhum
@
@ Comando enviado: 0xC0000000
@   - Bits [31:29] = 110 (opcode média de blocos - zoom out)
@=============================================================================
media_de_blocos:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #16
    str     r0, [sp, #0]
    str     r1, [sp, #4]
    str     r2, [sp, #8]
    str     lr, [sp, #12]

    @ Carrega comando de média de blocos
    ldr     r0, =0xC0000000

    @ Obtém ponteiro de instruções
    ldr     r1, =ponteiro_instrucoes
    ldr     r1, [r1]

    @ Envia comando para a FPGA
    str     r0, [r1]

    @ --- Restaurar registradores da pilha ---
    ldr     r0, [sp, #0]
    ldr     r1, [sp, #4]
    ldr     r2, [sp, #8]
    ldr     lr, [sp, #12]
    add     sp, sp, #16

    bx      lr


@=============================================================================
@ Função: nop (interna/privada)
@ Descrição: Envia instrução NOP (no operation) para a FPGA.
@
@ Parâmetros: Nenhum
@ Retorno: Nenhum
@
@ Comando enviado: 0x00000000
@=============================================================================
nop:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #12
    str     r0, [sp, #0]
    str     r1, [sp, #4]
    str     r2, [sp, #8]

    @ Carrega comando NOP
    ldr     r0, =0x00000000

    @ Obtém ponteiro de instruções
    ldr     r1, =ponteiro_instrucoes
    ldr     r1, [r1]

    @ Envia comando para a FPGA
    str     r0, [r1]

    @ --- Restaurar registradores da pilha ---
    ldr     r0, [sp, #0]
    ldr     r1, [sp, #4]
    ldr     r2, [sp, #8]
    add     sp, sp, #12

    bx      lr


@=============================================================================
@ Função: fechar_enderecos
@ Descrição: Libera os recursos alocados: desmapeia a memória e fecha os
@            file descriptors abertos (/dev/mem e arquivo de imagem).
@
@ Parâmetros: Nenhum
@ Retorno: Nenhum
@
@ Syscalls utilizadas:
@   - munmap (91): Desmapeia região de memória
@   - close (6): Fecha file descriptors
@=============================================================================
fechar_enderecos:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #12
    str     r0, [sp, #0]
    str     r1, [sp, #4]
    str     r7, [sp, #8]

    @ --- Syscall munmap(ponteiro_instrucoes, 0x5000) ---
    ldr     r0, =ponteiro_instrucoes
    ldr     r0, [r0]                @ r0 = endereço mapeado
    ldr     r1, =0x00005000         @ r1 = tamanho da região
    mov     r7, #91                 @ r7 = syscall number (munmap)
    svc     0                       @ executa syscall

    @ --- Syscall close(fd_devmem) ---
    ldr     r0, =ponteiro_fd
    ldr     r0, [r0]                @ r0 = file descriptor de /dev/mem
    mov     r7, #6                  @ r7 = syscall number (close)
    svc     0                       @ executa syscall

    @ --- Syscall close(fd_imagem) ---
    ldr     r0, =ponteiro_fd_imagem
    ldr     r0, [r0]                @ r0 = file descriptor da imagem
    mov     r7, #6                  @ r7 = syscall number (close)
    svc     0                       @ executa syscall

    @ --- Restaurar registradores da pilha ---
    ldr     r0, [sp, #0]
    ldr     r1, [sp, #4]
    ldr     r7, [sp, #8]
    add     sp, sp, #12

    bx      lr


@=============================================================================
@ SEÇÃO DE DADOS
@=============================================================================
.section .data

@-----------------------------------------------------------------------------
@ Strings de Caminhos de Arquivos
@-----------------------------------------------------------------------------
dev_mem:
    .asciz "/dev/mem"               @ Dispositivo de acesso à memória física

nome_arquivo:
    .asciz "imagem.pgm"             @ Nome do arquivo de imagem de entrada

@-----------------------------------------------------------------------------
@ Buffers e Variáveis Globais
@-----------------------------------------------------------------------------
    .equ buffer_size, 81920         @ Tamanho máximo do buffer (não utilizado)

input_buffer:
    .space 76800                    @ Buffer para imagem 320x240 (76800 bytes)

ponteiro_instrucoes:
    .space 4                        @ Ponteiro mapeado para registrador de instruções

ponteiro_imagem:
    .space 4                        @ Ponteiro auxiliar para imagem (reservado)

ponteiro_fd:
    .space 4                        @ File descriptor de /dev/mem

ponteiro_fd_imagem:
    .space 4                        @ File descriptor do arquivo de imagem

