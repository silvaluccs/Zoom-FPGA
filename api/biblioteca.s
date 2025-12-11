@=============================================================================
@ Arquivo: fpga_control.s
@ Descrição: Biblioteca em Assembly ARM para comunicação com FPGA via mapeamento
@            de memória. Permite enviar imagens e comandos de processamento
@            (zoom in/out, controle de exibição) para um coprocessador de
@            imagem em hardware Verilog.
@
@ Plataforma: ARM Linux (DE1-SoC / Cyclone V)
@ Resolução de Imagem: 320x240 pixels (76800 bytes)
@=============================================================================

.section .text

@-----------------------------------------------------------------------------
@ Declaração de Símbolos Globais (exportados para uso em C)
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

.global enviar_pixel
.type enviar_pixel, %function

.global carregar_pixel
.type carregar_pixel, %function

.global controle_imagem
.type controle_imagem, %function


@=============================================================================
@ Função: carregar_pixel
@ Descrição: Lê um pixel da memória do coprocessador FPGA.
@            Envia comando de leitura e aguarda o valor retornado.
@
@ Parâmetros: 
@   r0 = endereço do pixel (0 a 76799)
@   r1 = memória de exibição (0 ou 1)
@
@ Retorno: 
@   r0 = valor do pixel lido (0 a 255)
@
@ Formato da instrução de leitura:
@   [31:29] = 001 (opcode leitura)
@   [28:12] = endereço (17 bits)
@   [11]    = memória de exibição (1 bit)
@   [10:0]  = reservado
@=============================================================================
carregar_pixel:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #32
    str     r2, [sp, #0]
    str     r3, [sp, #4]
    str     r4, [sp, #8]
    str     r5, [sp, #12]
    str     r6, [sp, #16]
    str     r7, [sp, #20]
    str     lr, [sp, #24]
    str     r0, [sp, #28]              @ Backup de r0

    @ Salva parâmetros em registradores de trabalho
    mov     r5, r0                      @ r5 = endereço
    mov     r6, r1                      @ r6 = memória de exibição

    @ Carrega ponteiros dos registradores da FPGA
    ldr     r0, =ponteiro_instrucoes
    ldr     r0, [r0]                    @ r0 = endereço do registrador de instruções

    ldr     r2, =ponteiro_data
    ldr     r2, [r2]                    @ r2 = endereço do registrador de dados

    @ --- Monta instrução de leitura ---
    @ Opcode: 0b001 nos bits [31:29]
    mov     r4, #0b001
    lsl     r4, r4, #29

    @ Endereço nos bits [28:12]
    lsl     r5, r5, #12

    @ Memória de exibição no bit [11]
    lsl     r6, r6, #11

    @ Combina todos os campos
    orr     r4, r4, r5
    orr     r4, r4, r6

    @ Envia instrução de leitura para a FPGA
    str     r4, [r0]

esperando_pixel:
    @ Aguarda e lê o pixel do registrador de dados
    ldr     r4, [r3]                    @ Lê status (verificação futura)
    cmp     r4, #1                      @ Verifica se dado está pronto

    ldr     r6, [r2]                    @ r6 = pixel lido do registrador de dados

    @ Envia NOP para finalizar operação
    mov     r5, #0
    str     r5, [r0]

    @ Prepara retorno
    mov     r0, r6                      @ r0 = valor do pixel

    @ --- Restaurar registradores da pilha ---
    ldr     r2, [sp, #0]
    ldr     r3, [sp, #4]
    ldr     r4, [sp, #8]
    ldr     r5, [sp, #12]
    ldr     r6, [sp, #16]
    ldr     r7, [sp, #20]
    ldr     lr, [sp, #24]
    add     sp, sp, #32

    bx      lr


@=============================================================================
@ Função: enviar_pixel
@ Descrição: Escreve um pixel individual na memória da FPGA.
@            Utilizado para atualização parcial da imagem.
@
@ Parâmetros: 
@   r0 = valor do pixel (0 a 255)
@   r1 = endereço do pixel (0 a 76799)
@
@ Retorno: Nenhum
@
@ Formato da instrução de escrita:
@   [31:29] = 111 (opcode escrita)
@   [28:12] = endereço (17 bits)
@   [11:4]  = valor do pixel (8 bits)
@   [3:0]   = reservado
@=============================================================================
enviar_pixel:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #40
    str     r0, [sp, #0]
    str     r1, [sp, #4]
    str     r2, [sp, #8]
    str     r3, [sp, #12]
    str     r4, [sp, #16]
    str     r5, [sp, #20]
    str     r6, [sp, #24]
    str     r7, [sp, #28]
    str     r8, [sp, #32]
    str     lr, [sp, #36]

    @ Salva parâmetros
    mov     r2, r0                      @ r2 = valor do pixel
    mov     r3, r1                      @ r3 = endereço

    @ Carrega ponteiro de instruções da FPGA
    ldr     r4, =ponteiro_instrucoes
    ldr     r4, [r4]

enviar:
    @ Verifica se todos os pixels foram enviados (limite de segurança)
    cmp     r3, #76800
    beq     fim_envio_pixel

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

    @ Envia instrução NOP (0x00000000) para finalizar
    mov     r0, #0
    str     r0, [r4]

fim_envio_pixel:
    @ --- Restaurar registradores da pilha ---
    ldr     r0, [sp, #0]
    ldr     r1, [sp, #4]
    ldr     r2, [sp, #8]
    ldr     r3, [sp, #12]
    ldr     r4, [sp, #16]
    ldr     r5, [sp, #20]
    ldr     r6, [sp, #24]
    ldr     r7, [sp, #28]
    ldr     r8, [sp, #32]
    ldr     lr, [sp, #36]
    add     sp, sp, #40

    bx      lr


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
@   - ponteiro_instrucoes: Offset 0x00 (registrador de comandos)
@   - ponteiro_data: Offset 0x30 (registrador de dados)
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
    ldr     r0, =dev_mem                @ r0 = caminho do dispositivo
    mov     r1, #2                      @ r1 = O_RDWR (leitura e escrita)
    mov     r2, #0                      @ r2 = modo (não usado)
    mov     r7, #5                      @ r7 = syscall number (open)
    svc     0                           @ executa syscall

    mov     r4, r0                      @ r4 = file descriptor retornado

    @ Armazena o file descriptor para uso posterior
    ldr     r0, =ponteiro_fd
    str     r4, [r0]

    @ --- Syscall mmap2(NULL, 0x5000, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0xFF200) ---
    mov     r0, #0                      @ r0 = addr (NULL = kernel escolhe)
    ldr     r1, =0x00005000             @ r1 = length (20KB)
    mov     r2, #3                      @ r2 = prot (PROT_READ | PROT_WRITE)
    mov     r3, #1                      @ r3 = flags (MAP_SHARED)
    mov     r4, r4                      @ r4 = fd (file descriptor)
    ldr     r5, =0xFF200                @ r5 = offset/4096 (0xFF200000 >> 12)
    mov     r7, #192                    @ r7 = syscall number (mmap2)
    svc     0                           @ executa syscall

    @ Calcula e armazena o ponteiro para registrador de instruções (offset 0x00)
    mov     r5, r0                      @ r5 = endereço base mapeado
    ldr     r6, =0x00000000             @ offset do registrador de instruções
    add     r6, r5, r6                  @ r6 = endereço final

    ldr     r0, =ponteiro_instrucoes
    str     r6, [r0]

    @ Calcula e armazena o ponteiro para registrador de dados (offset 0x30)
    ldr     r6, =0x00000030
    add     r6, r5, r6

    ldr     r0, =ponteiro_data
    str     r6, [r0]

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
@ Parâmetros: 
@   r0 = ponteiro para nome do arquivo (imagem.pgm)
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

    @ --- Syscall open("ponteiro_imagem", O_RDONLY) ---
    mov     r1, #0                      @ r1 = O_RDONLY
    mov     r2, #0                      @ r2 = modo (não usado)
    mov     r7, #5                      @ r7 = syscall number (open)
    svc     0                           @ executa syscall

    mov     r4, r0                      @ r4 = file descriptor

    @ Armazena o file descriptor da imagem
    ldr     r1, =ponteiro_fd_imagem
    str     r0, [r1]

    @ --- Lê e descarta o cabeçalho PGM (15 bytes) ---
    mov     r0, r4                      @ r0 = fd
    ldr     r1, =input_buffer           @ r1 = buffer temporário
    mov     r2, #15                     @ r2 = tamanho do cabeçalho
    mov     r7, #3                      @ r7 = syscall number (read)
    svc     0                           @ executa syscall

    @ --- Lê os dados da imagem (76800 bytes) ---
    mov     r0, r4                      @ r0 = fd
    ldr     r1, =input_buffer           @ r1 = buffer de destino
    mov     r2, #76800                  @ r2 = 320 * 240 pixels
    mov     r7, #3                      @ r7 = syscall number (read)
    svc     0                           @ executa syscall

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
@            Cada pixel é empacotado em uma instrução de 32 bits.
@
@ Parâmetros: 
@ r0 = ponteiro para dados da imagem (input_buffer)
@ Retorno: Nenhum
@
@ Formato da instrução de escrita:
@   [31:29] = 111 (opcode escrita)
@   [28:12] = endereço (17 bits, 0 a 76799)
@   [11:4]  = valor do pixel (8 bits, 0 a 255)
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

    mov     r6, r0                      @ r6 = ponteiro para dados da imagem

    @ Carrega ponteiro de instruções da FPGA
    ldr     r4, =ponteiro_instrucoes
    ldr     r4, [r4]

    mov     r3, #0                      @ r3 = contador de pixels (0 a 76799)

enviar_proximo_pixel:
    @ Verifica se todos os pixels foram enviados
    cmp     r3, #76800
    beq     fim_envio_imagem

    @ Carrega próximo pixel e incrementa ponteiro
    ldrb    r2, [r6], #1                @ r2 = valor do pixel, r6++

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
@            Cada pixel é replicado em um bloco 2x2, ampliando a imagem.
@
@ Parâmetros: 
@   r0 = coordenada X 
@   r1 = coordenada Y 
@
@ Retorno: Nenhum
@
@ Formato do comando:
@   [31:29] = 100 (opcode replicação)
@   [28:20] = coordenada X (9 bits)
@   [19:12] = coordenada Y (8 bits)
@   [11:0]  = reservado
@=============================================================================
replicacao_pixel:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #16
    str     r2, [sp, #0]
    str     r3, [sp, #4]
    str     r4, [sp, #8]
    str     lr, [sp, #12]

    @ Salva parâmetros
    mov     r3, r0                      @ r3 = coordenada X
    mov     r4, r1                      @ r4 = coordenada Y

    @ --- Monta comando de replicação ---
    ldr     r0, =0x80000000             @ Opcode base (bit 31 = 1, bits 30-29 = 00)

    @ Coordenada X nos bits [28:20]
    lsl     r3, r3, #20
    @ Coordenada Y nos bits [19:12]
    lsl     r4, r4, #12

    @ Combina campos
    orr     r0, r0, r3
    orr     r0, r0, r4

    @ Obtém ponteiro de instruções
    ldr     r1, =ponteiro_instrucoes
    ldr     r1, [r1]

    @ Envia comando para a FPGA
    str     r0, [r1]

    @ --- Restaurar registradores da pilha ---
    ldr     r2, [sp, #0]
    ldr     r3, [sp, #4]
    ldr     r4, [sp, #8]
    ldr     lr, [sp, #12]
    add     sp, sp, #16

    bx      lr


@=============================================================================
@ Função: vizinho_mais_proximo
@ Descrição: Envia comando de zoom in usando interpolação por vizinho mais
@            próximo. Método mais refinado que replicação simples.
@
@ Parâmetros: 
@   r0 = coordenada X
@   r1 = coordenada Y
@
@ Retorno: Nenhum
@
@ Formato do comando:
@   [31:29] = 011 (opcode vizinho mais próximo)
@   [28:20] = coordenada X (9 bits)
@   [19:12] = coordenada Y (8 bits)
@   [11:0]  = reservado
@=============================================================================
vizinho_mais_proximo:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #16
    str     r2, [sp, #0]
    str     r3, [sp, #4]
    str     r4, [sp, #8]
    str     lr, [sp, #12]

    @ Salva parâmetros
    mov     r3, r0                      @ r3 = coordenada X
    mov     r4, r1                      @ r4 = coordenada Y

    @ --- Monta comando de vizinho mais próximo ---
    ldr     r0, =0x60000000             @ Opcode (bits 31-29 = 011)

    @ Coordenada X nos bits [28:20]
    lsl     r3, r3, #20
    @ Coordenada Y nos bits [19:12]
    lsl     r4, r4, #12

    @ Combina campos
    orr     r0, r0, r3
    orr     r0, r0, r4

    @ Obtém ponteiro de instruções
    ldr     r1, =ponteiro_instrucoes
    ldr     r1, [r1]

    @ Envia comando para a FPGA
    str     r0, [r1]

    @ --- Restaurar registradores da pilha ---
    ldr     r2, [sp, #0]
    ldr     r3, [sp, #4]
    ldr     r4, [sp, #8]
    ldr     lr, [sp, #12]
    add     sp, sp, #16

    bx      lr


@=============================================================================
@ Função: decimacao
@ Descrição: Envia comando de zoom out usando decimação (amostragem).
@
@ Parâmetros: Nenhum
@ Retorno: Nenhum
@
@ Formato do comando:
@   [31:29] = 101 (opcode decimação)
@   [28:0]  = reservado
@=============================================================================
decimacao:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #16
    str     r0, [sp, #0]
    str     r1, [sp, #4]
    str     r2, [sp, #8]
    str     lr, [sp, #12]

    @ Carrega comando de decimação
    ldr     r0, =0xA0000000             @ Opcode (bits 31-29 = 101)

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
@ Formato do comando:
@   [31:29] = 110 (opcode média de blocos)
@   [28:0]  = reservado
@=============================================================================
media_de_blocos:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #16
    str     r0, [sp, #0]
    str     r1, [sp, #4]
    str     r2, [sp, #8]
    str     lr, [sp, #12]

    @ Carrega comando de média de blocos
    ldr     r0, =0xC0000000             @ Opcode (bits 31-29 = 110)

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
@ Função: controle_imagem
@ Descrição: Controla a exibição da imagem no monitor (liga/desliga).
@
@ Parâmetros: 
@   r0 = desligar (0 = ligar, 1 = desligar)
@
@ Retorno: Nenhum
@
@ Formato do comando:
@   [31:29] = 010 (opcode controle)
@   [28:1]  = reservado
@   [0]     = flag desligar (1 bit)
@=============================================================================
controle_imagem:
    @ --- Salvar registradores na pilha ---
    sub     sp, sp, #12
    str     r1, [sp, #0]
    str     r2, [sp, #4]
    str     r3, [sp, #8]

    @ Salva parâmetro
    mov     r3, r0                      @ r3 = flag desligar

    @ --- Monta comando de controle ---
    ldr     r0, =0x40000000             @ Opcode base (bits 31-29 = 010)
    orr     r0, r0, r3                  @ Adiciona flag no bit [0]

    @ Obtém ponteiro de instruções
    ldr     r1, =ponteiro_instrucoes
    ldr     r1, [r1]

    @ Envia comando para a FPGA
    str     r0, [r1]

    @ --- Restaurar registradores da pilha ---
    ldr     r1, [sp, #0]
    ldr     r2, [sp, #4]
    ldr     r3, [sp, #8]
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
    ldr     r0, [r0]                    @ r0 = endereço mapeado (instruções)
    ldr     r1, =0x00005000             @ r1 = tamanho da região
    mov     r7, #91                     @ r7 = syscall number (munmap)
    svc     0                           @ executa syscall

    @ --- Syscall munmap(ponteiro_data, 0x5000) ---
    ldr     r0, =ponteiro_data
    ldr     r0, [r0]                    @ r0 = endereço mapeado (dados)
    ldr     r1, =0x00005000             @ r1 = tamanho da região
    mov     r7, #91                     @ r7 = syscall number (munmap)
    svc     0                           @ executa syscall

    @ --- Syscall close(fd_devmem) ---
    ldr     r0, =ponteiro_fd
    ldr     r0, [r0]                    @ r0 = file descriptor de /dev/mem
    mov     r7, #6                      @ r7 = syscall number (close)
    svc     0                           @ executa syscall

    @ --- Syscall close(fd_imagem) ---
    ldr     r0, =ponteiro_fd_imagem
    ldr     r0, [r0]                    @ r0 = file descriptor da imagem
    mov     r7, #6                      @ r7 = syscall number (close)
    svc     0                           @ executa syscall

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
    .asciz "/dev/mem"                   @ Dispositivo de acesso à memória física

nome_arquivo:
    .asciz "imagem.pgm"                 @ Nome do arquivo de imagem de entrada

@-----------------------------------------------------------------------------
@ Buffers e Variáveis Globais
@-----------------------------------------------------------------------------
    .equ buffer_size, 81920             @ Tamanho máximo do buffer

input_buffer:
    .space 76800                        @ Buffer para imagem 320x240 (76800 bytes)

ponteiro_instrucoes:
    .space 4                            @ Ponteiro mapeado para registrador de instruções

ponteiro_data:
    .space 4                            @ Ponteiro mapeado para registrador de dados

ponteiro_imagem:
    .space 4                            @ Ponteiro auxiliar para imagem (reservado)

ponteiro_fd:
    .space 4                            @ File descriptor de /dev/mem

ponteiro_fd_imagem:
    .space 4                            @ File descriptor do arquivo de imagem


@=============================================================================
@ NOTAS DE IMPLEMENTAÇÃO
@=============================================================================
@ 
@ 1. PROTOCOLO DE COMUNICAÇÃO:
@    - Todas as instruções são palavras de 32 bits
@    - Opcode definido nos 3 bits mais significativos [31:29]
@    - Finalização de comandos sempre com NOP (0x00000000)
@
@ 2. OPCODES DISPONÍVEIS:
@    001 - Leitura de pixel
@    010 - Controle de exibição
@    011 - Zoom in (vizinho mais próximo)
@    100 - Zoom in (replicação de pixel)
@    101 - Zoom out (decimação)
@    110 - Zoom out (média de blocos)
@    111 - Escrita de pixel
@
@ 3. MAPEAMENTO DE MEMÓRIA:
@    - Base: 0xFF200000 (lightweight HPS-to-FPGA bridge)
@    - Registrador de instruções: Base + 0x00
@    - Registrador de dados: Base + 0x30
@
@ 4. FORMATO DE IMAGEM:
@    - Resolução fixa: 320x240 pixels
@    - Formato: PGM binário (P5)
@    - Profundidade: 8 bits por pixel (escala de cinza)
@    - Total de pixels: 76800 bytes
@
@============================================================================
