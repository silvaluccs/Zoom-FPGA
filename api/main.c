#include "api.h"
#include <stdio.h>

int main() {
  volatile int *instrucoes = NULL;
  volatile int *resposta = NULL;

  volatile int *arquivo = NULL;

  arquivo = abrir_imagem();

  if (arquivo == NULL) {

    printf("Ocorreu um erro ao abrir um arquivo.\n");
    return 0;
  }

  // Corrigir o nome da função para mapear_enderecos
  mapear_enderecos(instrucoes, resposta);

  if (instrucoes == NULL || resposta == NULL) {
    printf("Ocorreu um erro ao mapear os enderecos.\n");
    return 1;
  }

  char comando;
  int algoritmo_zoom_in = -1;

  do {

    printf("Selecione uma opereração:\n");
    printf("1 - Zoom In\n");
    printf("2 - Zoom Out\n");
    printf("3 - Vizinho mais próximo\n");
    printf("4 - Replicação de pixels\n");
    printf("5 - Decimação\n");
    printf("6 - Média de pixels\n");
    printf("q - Sair\n");

    printf("Comando: ");
    scanf("%c", &comando);

    switch (comando) {

    case '1':

      if (algoritmo_zoom_in == -1) {
        printf("Selecione o algoritmo de Zoom In (3 - Vizinho mais próximo, 4 "
               "- Replicação de pixels) antes de aplicar o Zoom In.\n ");
        continue;
      } else if (algoritmo_zoom_in == 0) {
        printf("O algoritmo selecionado para Zoom In não é compatível. "
               "Selecione um algoritmo de Zoom In primeiro.\n");
        continue;
      } else {
        zoom_in(instrucoes);
        printf("Zoom In aplicado com sucesso.\n");
      }

    case '2':

      if (algoritmo_zoom_in == -1) {
        printf(
            "Selecione o algoritmo de Zoom Out (5 - Decimação, 6 - Média de  "
            "de blocos) antes de aplicar o Zoom Out.\n ");
        continue;
      } else if (algoritmo_zoom_in == 1) {
        printf("O algoritmo selecionado não é compatível. "
               "Selecione um algoritmo de Zoom out primeiro.\n");
        continue;
      } else {
        printf("Zoom Out aplicado com sucesso.\n");

        zoom_out(instrucoes);
        break;
      }

      break;
    case '3':
      vizinho_mais_proximo(instrucoes);
      algoritmo_zoom_in = 1;
      printf("Algoritmo de Vizinho mais próximo selecionado para Zoom In.\n");
      break;
    case '4':
      replicacao_pixel(instrucoes);
      printf("Algoritmo de Replicação de pixels selecionado para Zoom In.\n");
      algoritmo_zoom_in = 1;
      break;
    case '5':
      decimacao(instrucoes);
      printf("Algoritmo de Decimação selecionado para Zoom Out.\n");
      algoritmo_zoom_in = 0;
      break;
    case '6':
      media_de_blocos(instrucoes);
      printf("Algoritmo de Média de blocos selecionado para Zoom Out.\n");
      algoritmo_zoom_in = 0;
      break;
    case 'q':
      printf("Saindo do programa.\n");
      break;
    default:
      printf("Comando inválido. Tente novamente.\n");
      continue;
    }

  } while (comando != 'q');

  return 0;
}
