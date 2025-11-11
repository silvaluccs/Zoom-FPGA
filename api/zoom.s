
@ Feito por luqueta (cria)
@
@
.section .data
DEV_MEM:
        .asciz "/dev/mem"

nome_arquivo: .asciz "imagem.pgm"  @ String com o nome do arquivo

    .equ BUFFER_SIZE, 81920         @ Sintaxe correta para .equ
    input_buffer: .space BUFFER_SIZE

    temp_instruction: .space 4

.section .text
.global _start

_start:

  bl abrir_imagem 

  mov r10, r0 

  ldr r0, =DEV_MEM
  mov r1, #2
  mov r2, #0
  mov r7, #5          

  svc 0              

  mov r4, r0          

  mov r0, #0
  ldr r1, =0x00005000  
  mov r2, #3          
  mov r3, #1
  mov r4, r4          
  ldr r5, =0xFF200  
  mov r7, #192        
  svc 0

  mov r5, r0          
  ldr r6, =0x00000000
  add r6, r5, r6      

  ldr r7, =0x00000010  
  add r7, r5, r7      
  

 mov r0, #6
 lsl r0, r0, #29
 str r0, [r6]


  bl function_sleeping

  mov r0, #1  
  str r0, [r7]

 bl function_sleeping


  mov r0, #0
  str r0, [r7]
 

 mov r0, r6
 mov r1, r7
 mov r2, r10

@ bl enviar_imagem_fpga
b close


@ A função abrir_imagem não precisa de argumentos (registrador R0 será o retorno)
abrir_imagem:
    push {r4, r5, r6}   @ Salva os registradores de uso geral e o endereço de retorno

    @ 1. ABRIR ARQUIVO
    ldr r0, =nome_arquivo
    mov r1, #0              @ O_RDONLY
    mov r2, #0              @ Permissões (não usadas para leitura)
    mov r7, #5              @ syscall 'open'
    swi #0
    mov r4, r0              @ R4 = File Descriptor (FD)


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
    add r0, r1, r2          @ R0 = Endereço do início dos dados de pixel

    pop {r4, r5, r6}    @ Restaura os registradores salvos
    bx lr                   @ Retorna

enviar_imagem_fpga:
  @ Função para enviar a imagem processada para a fpga
  @ argumentos:
  @  1: ponteiro para o endereco de envio das instrucoes
  @  2: ponteiro para o endereco de recepcao da resposta
  
 @ push {r0, r1, r3} @ salvando os registradores com os ponteiros para envio e recepcao

  push {r0, r1, r2, r4, r5, r6, lr} @ Salva todos os regs que serão usados (Incluindo LR para o BX no final)
  mov r4, r0 @ r5 = ponteiro para o endereco de envio das instrucoes
  mov r5, r1 @ r6 = ponteiro para o endereco de recepcao da resposta
  mov r6, r2
  mov r3, #0 @ contador de enderecos enviados


enviar_proximo_pixel:

  cmp r3, #76800 @ verificando se ja enviou todos os pixels
  beq fim_envio_imagem @ se sim, fim do envio da imagem

  ldrb r2, [r6], #1

  mov r0, #0b111 @ opcode
  lsl r0, r0, #29 @ deslocando para a posicao correta

  mov r1, r3 @ r1 = contador de enderecos enviados
  lsl r1, r1, #12 @ deslocando para a posicao correta

 @ mov r2, #0 @ r2 = valor do pixel (inicialmente 0) TODO: substituir pelo valor correto
  lsl r2, r2, #4 @ deslocando para a posicao correta

  orr r0, r0, r1 @ combinando opcode e endereco
  orr r0, r0, r2 @ combinando com o valor do pixel

  str r0, [r4]

  mov r0, #1
  str r0, [r5]

  mov r0, #0
  str r0, [r5]

  add r3, r3, #1 @ incrementando o contador de enderecos enviados

@  bl function_sleeping
  b enviar_proximo_pixel

fim_envio_imagem:
  @ caso tenha enviado todos os pixels
  @pop {r0, r1} @ restaurando os registradores
  mov r0, #0
  lsl r0, r0, #29
@  str r0, [r4]

  mov r0, #1
  str r0, [r5]

  mov r0, #0
  str r0, [r5]

  pop {r0, r1, r2, r4, r5, r6, lr} @ <<--- CORREÇÃO: Restaura todos os registradores
  bx lr


function_sleeping:
    ldr r2, =5000000
sleep_loop:
    sub r2, r2, #1
    cmp r2, #1
    bne sleep_loop    @ Corrigido de 'b.neq' para 'bne'
    bx lr

close:
