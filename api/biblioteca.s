.section .text

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


mapear_enderecos:

  sub sp, sp, #36         @ reserva 32 bytes na pilha (8 registradores * 4 bytes)
  str r0, [sp, #0]       @ armazena r0 na pilha
  str r1, [sp, #4]       @ armazena r1 na pilha
  str r2, [sp, #8]       @ armazena r2 na pilha
  str r3, [sp, #12]      @ armazena r3 na pilha
  str r4, [sp, #16]      @ armazena r4 na pilha
  str r5, [sp, #20]      @ armazena r5 na pilha
  str r6, [sp, #24]      @ armazena r6 na pilha
  str r7, [sp, #28]      @ armazena r7 na pilha
  str lr, [sp, #32]

    ldr r0, =dev_mem       @ carrega o endereço de dev_mem em r0
    mov r1, #2             @ carrega o valor 2 em r1
    mov r2, #0             @ carrega o valor 0 em r2
    mov r7, #5             @ configura o valor do código do sistema (svc)
    
    svc 0                  @ chamada de sistema (svc)

    mov r4, r0             @ armazena o valor retornado em r0 em r4

    ldr r0, =ponteiro_fd
    str r4, [r0]

    mov r0, #0             @ limpa r0
    ldr r1, =0x00005000    @ carrega o valor 0x00005000 em r1
    mov r2, #3             @ carrega o valor 3 em r2
    mov r3, #1             @ carrega o valor 1 em r3
    mov r4, r4             @ (sem alteração, apenas para manter o valor de r4)
    ldr r5, =0xff200       @ carrega o endereço 0xff200 em r5
    mov r7, #192           @ configura o código do serviço (svc)
    
    svc 0                  @ chamada de sistema (svc)

    mov r5, r0             @ armazena o valor retornado em r0 em r5
    ldr r6, =0x00000000    @ carrega o valor 0x00000000 em r6
    add r6, r5, r6         @ realiza a soma de r5 e r6 (resultando em r5)

    ldr r0, =ponteiro_instrucoes
    str r6, [r0]
    
    mov r4, r6
    
    ldr r6, =0x00000010    @ carrega o valor 0x00000010 em r7
    add r6, r5, r6         @ soma o valor de r5 e r7 (resulta em r7)

    ldr r0, =ponteiro_enable
    str r6, [r0]
    
 
  ldr r0, [sp, #0]        @ restaura r0
  ldr r1, [sp, #4]        @ restaura r1
  ldr r2, [sp, #8]        @ restaura r2
  ldr r3, [sp, #12]       @ restaura r3
  ldr r4, [sp, #16]       @ restaura r4
  ldr r5, [sp, #20]       @ restaura r5
  ldr r6, [sp, #24]       @ restaura r6
  ldr r7, [sp, #28]       @ restaura r7
  ldr lr, [sp, #32]

  add sp, sp, #36         @ restaura o ponteiro da pilha (libera os 32 bytes)

  bx lr

@ a função abrir_imagem não precisa de argumentos (registrador r0 será o retorno)
@ a função abrir_imagem não precisa de argumentos (registrador r0 será o retorno)

abrir_imagem:
    @ --- salvar registradores usados ---
    sub     sp, sp, #24
    str     r4, [sp, #0]
    str     r7, [sp, #4]
    str     lr, [sp, #8]
    str     r1, [sp, #12]
    str     r2, [sp, #16]
    str     r3, [sp, #20]

    ldr     r0, =nome_arquivo   @ caminho do arquivo
    mov     r1, #0              @ O_RDONLY
    mov     r2, #0
    mov     r7, #5              @ syscall open
    svc     0
    mov     r4, r0              @ r4 = descritor de arquivo
 
   ldr     r1, =ponteiro_fd_imagem
   str     r0, [r1]

    mov     r0, r4
    ldr     r1, =input_buffer
    mov     r2, #15
    mov     r7, #3              @ syscall read
    svc     0

    mov     r0, r4
    ldr     r1, =input_buffer
    mov     r2, #76800          @ tamanho da imagem
    mov     r7, #3              @ syscall read
    svc     0

    ldr     r0, =input_buffer

    ldr     r4, [sp, #0]
    ldr     r7, [sp, #4]
    ldr     lr, [sp, #8]
    ldr     r1, [sp, #12]
    ldr     r2, [sp, #16]
    ldr     r3, [sp, #20]
    add     sp, sp, #24

    bx      lr                  @ retorna r0 = &input_buffer


enviar_imagem_fpga:
  @ função para enviar a imagem processada para a fpga
  @ argumentos:


  @ salva os registradores usados na pilha
  sub sp, sp, #36         @ reserva 32 bytes na pilha (8 registradores * 4 bytes)
  str r0, [sp, #0]       @ armazena r0 na pilha
  str r1, [sp, #4]       @ armazena r1 na pilha
  str r2, [sp, #8]       @ armazena r2 na pilha
  str r3, [sp, #12]      @ armazena r3 na pilha
  str r4, [sp, #16]      @ armazena r4 na pilha
  str r5, [sp, #20]      @ armazena r5 na pilha
  str r6, [sp, #24]      @ armazena r6 na pilha
  str r7, [sp, #28]      @ armazena r7 na pilha
  str lr, [sp, #32]

  bl abrir_imagem

  mov r6, r0
  ldr r4, =ponteiro_instrucoes
  ldr r4, [r4]

  ldr r5, =ponteiro_enable
  ldr r5, [r5]
  
  mov r3, #0  @ contador de enderecos enviados

enviar_proximo_pixel:
  cmp r3, #76800          @ verificando se já enviou todos os pixels
  beq fim_envio_imagem    @ se sim, fim do envio da imagem

  ldrb r2, [r6], #1       @ carrega o valor do pixel e incrementa o ponteiro de recepção

  mov r0, #0b111          @ opcode
  lsl r0, r0, #29         @ deslocando para a posição correta

  mov r1, r3              @ r1 = contador de endereços enviados
  lsl r1, r1, #12         @ deslocando para a posição correta

  @ mov r2, #0           @ r2 = valor do pixel (inicialmente 0) todo: substituir pelo valor correto
  lsl r2, r2, #4          @ deslocando para a posição correta

  orr r0, r0, r1          @ combinando opcode e endereço
  orr r0, r0, r2          @ combinando com o valor do pixel

  str r0, [r4]            @ envia o valor para o endereço de envio das instruções

  mov r0, #1
  str r0, [r5]            @ envia o valor 1 para o endereço de recepção

  mov r0, #0
  str r0, [r5]            @ envia o valor 0 para o endereço de recepção

  add r3, r3, #1          @ incrementa o contador de endereços enviados

  @ bl function_sleeping
  b enviar_proximo_pixel   @ continua enviando o próximo pixel

fim_envio_imagem:
  @ caso tenha enviado todos os pixels

  mov r0, #0

  str r0, [r4]            @ envia o valor para o endereço de envio das instruções

  mov r0, #1
  str r0, [r5]            @ envia o valor 1 para o endereço

  mov r0, #0
  str r0, [r5]            @ envia o valor 0 para o endereço


  @ restaura os registradores da pilha
  ldr r0, [sp, #0]        @ restaura r0
  ldr r1, [sp, #4]        @ restaura r1
  ldr r2, [sp, #8]        @ restaura r2
  ldr r3, [sp, #12]       @ restaura r3
  ldr r4, [sp, #16]       @ restaura r4
  ldr r5, [sp, #20]       @ restaura r5
  ldr r6, [sp, #24]       @ restaura r6
  ldr r7, [sp, #28]       @ restaura r7
  ldr lr, [sp, #32]

  add sp, sp, #36         @ restaura o ponteiro da pilha (libera os 32 bytes)


  bx lr                  @ retorna

replicacao_pixel:
    sub sp, sp, #12
    str r0, [sp, #0]
    str r1, [sp, #4]
    str r2, [sp, #8]

    ldr r0, =0x80000000    @ Carrega o comando

    ldr r1, =ponteiro_instrucoes
    ldr r1, [r1]

    ldr r2, =ponteiro_enable
    ldr r2, [r2]

    str r0, [r1]

    mov r0, #1
    str r0, [r2]

    mov r0, #0
    str r0, [r2]

    ldr r0, [sp, #0]
    ldr r1, [sp, #4]
    ldr r2, [sp, #8]
    add sp, sp, #12

    bx lr                  @ Retorna


vizinho_mais_proximo:
    sub sp, sp, #12
    str r0, [sp, #0]
    str r1, [sp, #4]
    str r2, [sp, #8]

    ldr r0, =0x60000000    @ Carrega o comando

    ldr r1, =ponteiro_instrucoes
    ldr r1, [r1]

    ldr r2, =ponteiro_enable
    ldr r2, [r2]

    str r0, [r1]

    mov r0, #1
    str r0, [r2]

    mov r0, #0
    str r0, [r2]

    ldr r0, [sp, #0]
    ldr r1, [sp, #4]
    ldr r2, [sp, #8]
    add sp, sp, #12

    bx lr                  @ Retorna


decimacao:
    sub sp, sp, #16
    str r0, [sp, #0]
    str r1, [sp, #4]
    str r2, [sp, #8]
    str lr, [sp, #12]

    ldr r0, =0xA0000000    @ Carrega o comando

    ldr r1, =ponteiro_instrucoes
    ldr r1, [r1]

    ldr r2, =ponteiro_enable
    ldr r2, [r2]

    str r0, [r1]

    mov r0, #1
    str r0, [r2]

  @  bl function_sleeping

    mov r0, #0
    str r0, [r2]


    ldr r0, [sp, #0]
    ldr r1, [sp, #4]
    ldr r2, [sp, #8]
    ldr lr, [sp, #12]
    add sp, sp, #16

    bx lr                  @ Retorna


media_de_blocos:
    sub sp, sp, #16
    str r0, [sp, #0]
    str r1, [sp, #4]
    str r2, [sp, #8]
    str lr, [sp, #12]

    ldr r0, =0xC0000000    @ Carrega o comando

    ldr r1, =ponteiro_instrucoes
    ldr r1, [r1]

    ldr r2, =ponteiro_enable
    ldr r2, [r2]

    str r0, [r1]

    mov r0, #1
    str r0, [r2]

    mov r0, #0
    str r0, [r2]

    ldr r0, [sp, #0]
    ldr r1, [sp, #4]
    ldr r2, [sp, #8]
    ldr lr, [sp, #12]
    add sp, sp, #16

    bx lr                  @ Retorna


nop:
  sub sp, sp, #12
  str r0, [sp, #0]
  str r1, [sp, #4]
  str r2, [sp, #8]

  ldr r0, =0x00000000    @ Carrega o comando

  ldr r1, =ponteiro_instrucoes
  ldr r1, [r1]

  ldr r2, =ponteiro_enable
  ldr r2, [r2]

  str r0, [r1]

  mov r0, #1
  str r0, [r2]

  mov r0, #0
  str r0, [r2]

  ldr r0, [sp, #0]
  ldr r1, [sp, #4]
  ldr r2, [sp, #8]
  add sp, sp, #12

  bx lr                  @ Retorna

fechar_enderecos:
        sub sp, sp, #12
        str r0, [sp, #0]
        str r1, [sp, #4]
        str r7, [sp, #8]

        ldr r0, =ponteiro_instrucoes
        ldr r0, [r0]
        ldr r1, =0x00005000 
        mov r7, #91

        svc 0


        ldr r0, =ponteiro_enable

        ldr r0, [r0]
        ldr r1, =0x00005000 
        mov r7, #91

        svc 0


        ldr r0, =ponteiro_fd
        ldr r0, [r0]
        mov r7, #6

        svc 0

	ldr r0, =ponteiro_fd_imagem
	ldr r0, [r0]
	mov r7, #6
	svc 0

        ldr r0, [sp, #0]
        ldr r1, [sp, #4]
        ldr r7, [sp, #8]
        add sp, sp, #12


        bx lr

function_sleeping:
    sub sp, sp, #4
    str r2, [sp, #0]   
    ldr r2, =15000000
sleep_loop:
    sub r2, r2, #1
    cmp r2, #1
    bne sleep_loop    @ Corrigido de 'b.neq' para 'bne'

 
    ldr r2, [sp, #0]
    add sp, sp, #4
 

    bx lr



.section .data
dev_mem:
        .asciz "/dev/mem"

nome_arquivo: .asciz "imagem.pgm"  @ string com o nome do arquivo

    .equ buffer_size, 81920         @ sintaxe correta para .equ
    input_buffer: .space 76800

    ponteiro_instrucoes: .space 4
    ponteiro_enable: .space 4
    ponteiro_imagem: .space 4
    ponteiro_fd:    .space 4
    ponteiro_fd_imagem: .space 4
