.data

    nome_arquivo: .asciz "imagem.pgm"  @ String com o nome do arquivo

    .equ BUFFER_SIZE, 81920         @ Sintaxe correta para .equ
    input_buffer: .space BUFFER_SIZE

    temp_instruction: .space 4

.text
.global _start

_start:
    ldr r0, =nome_arquivo
    mov r1, #0            @ O_RDONLY (Somente leitura)
    mov r2, #0            @ Permissões não são necessárias
    mov r7, #5            @ syscall 'open' (Número 5)
    swi #0
    mov r4, r0            @ Salva o descritor do arquivo em R4 (File Descriptor)

    cmp r4, #0
    blt file_error

    mov r0, r4            @ r0 = File Descriptor (R4)
    ldr r1, =input_buffer   @ r1 = Endereço do buffer de ENTRADA
    ldr r2, =BUFFER_SIZE  @ r2 = Tamanho máximo a ser lido (80KB)
    mov r7, #3            @ syscall 'read' (Número 3)
    swi #0
    @ R8 = Número total de bytes lidos (não usado diretamente, mas bom ter)
    @ mov r8, r0

    ldr r1, =input_buffer   @ R1 = Endereço base do buffer
    mov r2, #0            @ R2 = Contador de bytes (offset/tamanho do cabeçalho)
    mov r3, #0            @ R3 = Contador de novas linhas encontradas
    mov r5, #10           @ R5 = Valor ASCII para nova linha ('\n')

find_header_end_loop:
    ldrb r6, [r1, r2]     @ Carrega 1 byte do buffer (endereço_base + índice)
    add r2, r2, #1        @ Incrementa o índice para o próximo byte
    cmp r6, r5            @ Compara o byte com '\n'
    addeq r3, r3, #1      @ Se for igual, incrementa o contador de novas linhas
    cmp r3, #3            @ Já encontramos 3 novas linhas? (Fim do cabeçalho PGM)
    bne find_header_end_loop @ Se não, continua o loop

    @ Neste ponto:
    @ R1 (input_buffer) + R2 é o endereço do início dos dados de pixel.
    
    @ R1 aponta para o INÍCIO DOS DADOS DE PIXEL
    add r1, r1, r2        @ R1 = Endereço do input_buffer + offset_do_cabeçalho


    @ --- 4. PROCESSAR PIXELS E GERAR INSTRUÇÕES ---
    
    mov r5, #0            @ R5 = Índice do pixel (o endereço de 17 bits)

process_loop:
    cmp r5, #76800
    bge end_process       @ Se sim, termina.

    ldrb r6, [r1], #1     @ R6 = Valor do pixel. R1 é incrementado em 1.

    @ Formato: [000 (3)] [Índice (17)] [Pixel (8)] [Sobra (4)]
    
    mov r7, r5
    lsl r7, r7, #12       @ R7 = [000][Índice (17)][zeros (12)]
    
    lsl r6, r6, #4        @ R6 = [zeros (24)][Pixel (8)][zeros (4)]

    @ Combina o índice e o pixel
    orr r7, r7, r6        @ R7 agora tem o formato [000][Índice][Pixel][0000]

    @ 4. Imprime a instrução (os 4 bytes do buffer) no stdout
    mov r1, r0            @ R1 = Endereço do buffer com a instrução
    mov r0, #1            @ R0 = 1 (stdout)
    mov r2, #4            @ R2 = 4 bytes
    mov r7, #4            @ R7 = syscall 'write'
    swi #0

    @ 5. Incrementa o índice do pixel e continua o loop
    add r5, r5, #1
    b process_loop
        
end_process:
    mov r0, r4            @ r0 = File Descriptor (R4)
    mov r7, #6            @ syscall 'close' (Número 6)
    swi #0

    mov r0, #0
    mov r7, #1            @ syscall 'exit' (Número 1)
    swi #0

@ Trata o erro de abertura de arquivo
file_error:
    @ (Opcional: imprimir uma mensagem de erro no stderr)
    mov r0, #1            @ r0 = Código de saída de erro
    mov r7, #1            @ syscall 'exit'
    swi #0
