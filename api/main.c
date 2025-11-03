#include <stdio.h>
#include "api.h"

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

    enviar_imagem_fpga(instrucoes, resposta, arquivo);
    return 0;
}

