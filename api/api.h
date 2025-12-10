#ifndef API_H
#define API_H

// Alterando para aceitar ponteiros volatile
void mapear_enderecos();
void enviar_imagem_fpga(char *imagem);

void replicacao_pixel(int x, int y);
void vizinho_mais_proximo(int x, int y);
void decimacao();
void media_de_blocos();
void fechar_enderecos();

void controle_imagem(int desligar);


void enviar_pixel(int pixel, int endereco);

int carregar_pixel(int endereco, int memoria_exibicao);

#endif // API_H
