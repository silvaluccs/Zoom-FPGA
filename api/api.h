#ifndef API_H
#define API_H

// Alterando para aceitar ponteiros volatile
extern int *abrir_imagem();

extern void mapear_enderecos(volatile int *instrucoes, volatile int *resposta);

extern void enviar_imagem_fpga(volatile int *instrucoes, volatile int *resposta,
                               volatile int *arquivo);

extern void replicacao_pixel(volatile int *instrucoes);

extern void vizinho_mais_proximo(volatile int *instrucoes);

extern void decimacao(volatile int *instrucoes);

extern void media_de_blocos(volatile int *instrucoes);

extern void nop(volatile int *instrucoes);

extern void zoom_in(volatile int *instrucoes);

extern void zoom_out(volatile int *instrucoes);

#endif // API_H
