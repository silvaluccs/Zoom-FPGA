#ifndef API_H
#define API_H

// Alterando para aceitar ponteiros volatile
extern int mapear_enderecos();

extern void enviar_imagem_fpga();
extern void replicacao_pixel();

extern void vizinho_mais_proximo();

extern void decimacao();

extern void media_de_blocos();

extern void nop();

extern void zoom_in();

extern void zoom_out();

#endif // API_H
