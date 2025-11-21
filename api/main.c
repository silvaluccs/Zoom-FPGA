#include "api.h"
#include <stdio.h>
#include <stdlib.h>

int main() {
  // A função mapear_enderecos deve ser chamada apenas uma vez para configurar o
  // acesso à FPGA.
  printf("mapeando enderecos...\n");
  mapear_enderecos();
  printf("enderecos mapeados com sucesso.\n");

  char comando;

  while (1) {
    // Exibindo o menu de opções
    printf("\n==================================\n");
    printf("Selecione uma operacao:\n");
    printf("1 - Vizinho mais proximo\n");
    printf("2 - Replicacao de pixels\n");
    printf("3 - Decimacao\n");
    printf("4 - Media de pixels\n");
    printf("5 - Envia imagem para FPGA\n");
    printf("q - Sair\n");
    printf("==================================\n");

    // Lendo o comando do usuário
    do {
      printf("Comando: ");
      int result =
          scanf(" %c", &comando); // O espaço antes de %c para limpar o buffer

      if (result != 1) {
        // Se a leitura falhar, limpe o buffer e avise o usuário
        printf("Entrada invalida! Tente novamente.\n");
        while (getchar() != '\n')
          ; // Limpar o buffer de entrada
      } else {
        break; // Se a leitura foi bem-sucedida, sai do loop
      }
    } while (1);

    // Exibe o comando lido (para depuração)
    printf("Comando lido: '%c'\n", comando);

    // Processando o comando
    if (comando == '1') {
      printf("Entrou no comando 1\n");
      vizinho_mais_proximo();
      printf("Operacao 'Vizinho mais proximo' enviada.\n");
    } else if (comando == '2') {
      printf("Entrou no comando 2\n");
      replicacao_pixel();
      printf("Operacao 'Replicacao de pixels' enviada.\n");
    } else if (comando == '3') {
      printf("Entrou no comando 3\n");
      decimacao();
      printf("Operacao 'Decimacao' enviada.\n");
    } else if (comando == '4') {
      printf("Entrou no comando 4\n");
      media_de_blocos();
      printf("Operacao 'Media de pixels' enviada.\n");
    } else if (comando == '5') {
      printf("Entrou no comando 5\n");
      enviar_imagem_fpga("imagem.pgm");
      printf("Imagem enviada para a FPGA.\n");
    } else if (comando == 'q') {
      printf("Saindo do programa...\n");
      break; // Sai do loop e termina o programa
    } else {
      printf("Comando invalido. Tente novamente.\n");
    }
  }

  // Fechar endereços antes de sair
  fechar_enderecos();
  return 0;
}
