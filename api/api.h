#ifndef API_H
#define API_H

// Alterando para aceitar ponteiros volatile
extern int* abrir_imagem();
extern void mapear_enderecos(volatile int *instrucoes, volatile int *resposta);
extern void enviar_imagem_fpga(volatile int *instrucoes, volatile int *resposta, volatile int *arquivo);

#endif // API_H

