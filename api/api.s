

.section .text
    .global _start
    .global mapear_enderecos
    .global abrir_imagem
    .global enviar_imagem_fpga
    .global replicacao_pixel
    .global vizinho_mais_proximo
    .global decimacao
    .global media_de_blocos
    .global nop
    .global zoom_in
    .global zoom_out

    .type replicacao_pixel, %function
    .type vizinho_mais_proximo, %function
    .type decimacao, %function
    .type media_de_blocos, %function
    .type nop, %function
    .type zoom_in, %function
    .type zoom_out, %function
    .type enviar_imagem_fpga, %function
    .type abrir_imagem, %function
    .type mapear_enderecos, %function
    
abrir_imagem:
    push {r0, r1, r2, r3, r4, r5, r6, lr}   @ Salva todos os registradores de uso geral e o endereço de retorno

    @ 1. ABRIR ARQUIVO
    ldr r0, =nome_arquivo // TODO: substituir pelo nome do arquivo desejado
    mov r1, #0              @ O_RDONLY
    mov r2, #0              @ Permissões (não usadas para leitura)
    mov r7, #5              @ syscall 'open'
    swi #0
    mov r4, r0              @ R4 = File Descriptor (FD)

    cmp r4, #0
    blt file_error_abrir    @ Se FD <= 0, erro ao abrir

    @ 2. LER ARQUIVO PARA O BUFFER
    mov r0, r4              @ r0 = File Descriptor
    ldr r1, =input_buffer   @ r1 = Endereço do buffer de ENTRADA
    ldr r2, =BUFFER_SIZE    @ r2 = Tamanho máximo a ser lido
    mov r7, #3              @ syscall 'read'
    swi #0
    @ O resultado (bytes lidos) está em R0, mas não o usaremos explicitamente.

    @ 3. ENCONTRAR O FIM DO CABEÇALHO PGM (3 linhas)
    ldr r1, =input_buffer   @ R1 = Endereço base do buffer (Ponteiro para o início)
    mov r2, #0              @ R2 = Contador de bytes (offset)
    mov r3, #0              @ R3 = Contador de novas linhas encontradas
    mov r5, #10             @ R5 = Valor ASCII para nova linha ('\n')

find_header_end_loop:
    ldrb r6, [r1, r2]       @ Carrega 1 byte do buffer (R6)
    add r2, r2, #1          @ Incrementa o offset (R2)
    cmp r6, r5              @ Compara com '\n'
    addeq r3, r3, #1        @ Se igual, incrementa o contador de '\n'
    cmp r3, #3              @ Já encontramos 3 novas linhas?
    bne find_header_end_loop@ Se não, continua

    @ 4. FECHAR O ARQUIVO (IMPORTANTE!)
    mov r0, r4              @ r0 = File Descriptor (R4)
    mov r7, #6              @ syscall 'close'
    swi #0

    @ 5. PREPARAR RETORNO
    @ R0 deve ser o valor de retorno (ponteiro para o início dos dados de pixel)
    @ R0 = Endereço base do buffer (R1) + Offset do cabeçalho (R2)
    add r0, r1, r2          @ R0 = Endereço do início dos dados de pix

    pop {r0, r1, r2, r3, r4, r5, r6, lr}    @ Restaura todos os registradores salvos
    bx lr                   @ Retorna

file_error_abrir:
    @ A função falhou. R0 já está com o valor de erro (-1 ou similar)
    @ O chamador deve checar R0 < 0 para tratar o erro.
    pop {r0, r1, r2, r3, r4, r5, r6, lr}    @ Restaura todos os registradores
    mov r0, #0              @ Retorna NULL (0) em caso de erro
    bx lr                   @ Retorna


enviar_imagem_fpga:
  @ Função para enviar a imagem processada para a fpga
  @ argumentos:

  bl abrir_imagem

  mov r2, r0 @ r2 = ponteiro para o endereco da imagem
  ldr r0, =ponteiro_instrucoes
  

  push {r0, r1, r2, r4, r5, r6, lr} @ Salva todos os regs que serão usados (Incluindo LR para o BX no final)
  mov r4, r0 @ r5 = ponteiro para o endereco de envio das instrucoes
  mov r6, r2
  mov r3, #0 @ contador de enderecos enviados


enviar_proximo_pixel:

  cmp r3, #76800 @ verificando se ja enviou todos os pixels
  beq fim_envio_imagem @ se sim, fim do envio da imagem

  ldrb r2, [r6], #1

  mov r0, #0b000 @ opcode
  lsl r0, r0, #29 @ deslocando para a posicao correta

  mov r1, r3 @ r1 = contador de enderecos enviados
  lsl r1, r1, #12 @ deslocando para a posicao correta

 @ mov r2, #0 @ r2 = valor do pixel (inicialmente 0) TODO: substituir pelo valor correto
  lsl r2, r2, #4 @ deslocando para a posicao correta

  orr r0, r0, r1 @ combinando opcode e endereco
  orr r0, r0, r2 @ combinando com o valor do pixel

  str r0, [r4]

  add r3, r3, #1 @ incrementando o contador de enderecos enviados
  
  b enviar_proximo_pixel

fim_envio_imagem:
  @ caso tenha enviado todos os pixels
  @pop {r0, r1} @ restaurando os registradores
  mov r0, #7
  lsl r0, r0, #29
  str r0, [r4]
  pop {r0, r1, r2, r4, r5, r6, lr} @ <<--- CORREÇÃO: Restaura todos os registradores
  bx lr



mapear_enderecos:
  @ Função para mapear endereços de memória virutal da fpga
  @ argumentos:

  push {r0, r1, r2, r3, r4, r5, r6} @ Salva todos os registradores necessários

  @ abrindo o /dev/mem
  ldr r0, =DEV_MEM
  mov r1, #2
  mov r2, #0
  mov r7, #5          

  svc 0  

  cmp r0, #0
  blt erro_abrir_dev_mem

  mov r4, r0          

  @ mapeando o endereco virtual com nmap2
  mov r0, #0
  ldr r1, =0x00005000  
  mov r2, #3          
  mov r3, #1
  mov r4, r4          
  ldr r5, =0xFF200  
  mov r7, #192        
  svc 0

  mov r2, r0


  ldr r0, =0x00000000 
  add r0, r0, r2

  ldr r1, =ponteiro_instrucoes
  str r0, [r1]

  mov r0, #1

  pop {r0, r1, r2, r3, r4, r5, r6} @ Restaura os registradores
  bx lr


erro_abrir_dev_mem:
  @ caso haja erro ao abrir o /dev/mem
  mov r0, #0
  pop {r0, r1, r2, r3, r4, r5, r6} @ Restaura os registradores
  bx lr


replicacao_pixel:
  @ Funcao para selecionar o algoritmo de replicacao_pixel
  @ Opcode 100

  ldr r0, =ponteiro_instrucoes

  push {r0, r1}


  ldr r1, =0x80000000 @ Carrega o opcode 100 na posicao correta

  str r1, [r0]        @ Envia a instrucao para o endereco de envio

  pop {r0, r1}

  bx lr


vizinho_mais_proximo:
  @ Funcao para selecionar o algoritmo de vizinho_mais_proximo
  @ Opcode 011

  ldr r0, =ponteiro_instrucoes

  push {r0, r1}

  ldr r1, =0x60000000 @ Carrega o opcode 011 na posicao correta

  str r1, [r0]        @ Envia a instrucao para o endereco de envio

  pop {r0, r1}

  bx lr

decimacao:
  @ Funcao para selecionar o algoritmo de vizinho_mais_proximo
  @ Ponteiro para o envio das instrucoes em r0
  @ Opcode 101

  ldr r0, =ponteiro_instrucoes

  push {r0, r1}

  ldr r1, =0xA0000000 @ Carrega o opcode 101 na posicao correta

  str r1, [r0]        @ Envia a instrucao para o endereco de envio

  pop {r0, r1}

  bx lr

media_de_blocos:
  @ Funcao para selecionar o algoritmo de media_de_blocos
  @ Opcode 110

  ldr r0, =ponteiro_instrucoes

  push {r0, r1}

  ldr r1, =0xC0000000 @ Carrega o opcode 110 na posicao correta

  str r1, [r0]        @ Envia a instrucao para o endereco de envio

  pop {r0, r1}

  bx lr


nop:
  @ Funcao para enviar uma instrucao NOP
  @ Opcode 111

  ldr r0, =ponteiro_instrucoes

  push {r0, r1}

  ldr r1, =0xE0000000 @ Carrega o opcode 111 na posicao correta

  str r1, [r0]        @ Envia a instrucao para o endereco de envio

  pop {r0, r1}

  bx lr


zoom_in:
  @ Funcao para enviar o comando de zoom in
  @ Ponteiro para o envio das instrucoes em r0
  @ Opcode 001

  ldr r0, =ponteiro_instrucoes

  push {r0, r1}

  ldr r1, =0x20000000 @ Carrega o opcode 001 na posicao correta

  str r1, [r0]        @ Envia a instrucao para o endereco de envio

  pop {r0, r1}

  bx lr


zoom_out:
  @ Funcao para enviar o comando de zoom out
  @ Ponteiro para o envio das instrucoes em r0
  @ Opcode 010

  ldr r0, =ponteiro_instrucoes

  push {r0, r1} 

  ldr r1, =0x40000000 @ Carrega o opcode 010 na posicao correta

  str r1, [r0]        @ Envia a instrucao para o endereco de envio

  pop {r0, r1}

  bx lr


.section .data
DEV_MEM:
        .asciz "/dev/mem"

nome_arquivo: .asciz "imagem.pgm"  @ String com o nome do arquivo

    .equ BUFFER_SIZE, 81920         @ Sintaxe correta para .equ
    input_buffer: .space BUFFER_SIZE

    temp_instruction: .space 4
    ponteiro_instrucoes: .space 4




