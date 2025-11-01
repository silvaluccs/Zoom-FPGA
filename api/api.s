    .section .text
    .global _start
    .global mapear_enderecos
    .global enviar_imagem_fpga
    .type enviar_imagem_fpga, %function
    .type mapear_enderecos, %function


enviar_imagem_fpga:
  // Função para enviar a imagem processada para a fpga
  // argumentos:
  //  1: ponteiro para o endereco de envio das instrucoes
  //  2: ponteiro para o endereco de recepcao da resposta
  
  push {r0, r1} // salvando os registradores com os ponteiros para envio e recepcao

  mov r4, r0 // r5 = ponteiro para o endereco de envio das instrucoes
  mov r5, r1 // r6 = ponteiro para o endereco de recepcao da resposta

  mov r3, #0 // contador de enderecos enviados


enviar_proximo_pixel:

  cmp r3, #76800 // verificando se ja enviou todos os pixels
  beq fim_envio_imagem // se sim, fim do envio da imagem

  mov r0, #0b000- // opcode
  lsl r0, r0, #29 // deslocando para a posicao correta

  mov r1, r3 // r1 = contador de enderecos enviados
  lsl r1, r1, #12 // deslocando para a posicao correta

  mov r2, #0 // r2 = valor do pixel (inicialmente 0) TODO: substituir pelo valor correto
  lsl r2, r2, #4 // deslocando para a posicao correta

  orr r0, r0, r1 // combinando opcode e endereco
  orr r0, r0, r2 // combinando com o valor do pixel

  str r0, [r4]

  add r3, r3, #1 // incrementando o contador de enderecos enviados

esperando_resposta:
  // aguardando a resposta da fpga
  ldr r0, [r5]

  cmp r0, #1
  beq enviar_proximo_pixel

  b esperando_resposta

fim_envio_imagem:
  // caso tenha enviado todos os pixels
  pop {r0, r1} // restaurando os registradores
  bx lr




mapear_enderecos:
  // Função para mapear endereços de memória virutal da fpga
  // argumentos:
  //  1: ponteiro para o endereco de envio das instrucoes
  //  2: ponteiro para o endereco de recepcao da resposta

  push {r0, r1}

  // abrindo o /dev/mem
  ldr r0, =DEV_MEM
  mov r1, #2
  mov r2, #0
  mov r7, #5          

  svc 0  

  cmp r0, #0
  blt erro_abrir_dev_mem

  mov r4, r0          

  // mapeando o endereco virtual com nmap2
  mov r0, #0
  ldr r1, =0x00005000  
  mov r2, #3          
  mov r3, #1
  mov r4, r4          
  ldr r5, =0xFF200  
  mov r7, #192        
  svc 0

  mov r2, r0

  pop {r0, r1}

  ldr r0, =0x00000000 
  add r0, r0, r2

  ldr r1, =0x00000010  
  add r1, r1, r2

  bx lr


erro_abrir_dev_mem:
  // caso haja erro ao abrir o /dev/mem
  pop {r0, r1}
  bx lr


.section .data
DEV_MEM:
        .asciz "/dev/mem"


