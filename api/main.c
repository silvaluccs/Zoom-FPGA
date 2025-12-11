/*==============================================================================
 * Arquivo: main.c
 * Descrição: Sistema interativo de controle de zoom para coprocessador FPGA
 *            Permite aplicar algoritmos de zoom in/out em imagens PGM através
 *            de interface de mouse e teclado.
 *
 * Funcionalidades:
 *   - Seleção de algoritmos de zoom in (vizinho mais próximo, replicação)
 *   - Seleção de algoritmos de zoom out (decimação, média de blocos)
 *   - Modo janela: zoom em região específica da imagem
 *   - Modo global: zoom na imagem inteira
 *   - Modo interativo: movimentação da janela em tempo real
 *
 * Hardware: DE1-SoC (Cyclone V) + Coprocessador Verilog
 * Resolução: 320x240 pixels (8 bits por pixel, escala de cinza)
 *============================================================================*/

#include "api.h"
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/input.h>
#include <sys/select.h>
#include <termios.h>
#include <string.h>

/*==============================================================================
 * CONSTANTES DO SISTEMA
 *============================================================================*/
#define SCREEN_WIDTH  320           /* Largura da tela em pixels */
#define SCREEN_HEIGHT 240           /* Altura da tela em pixels */
#define TOTAL_PIXELS  76800         /* Total de pixels (320 * 240) */
#define MAX_WINDOW_SIZE 100         /* Tamanho máximo da janela de zoom */

/* Delays em microsegundos - ajustados para sincronização com FPGA */
#define DELAY_CURTO     3           /* 0.1ms - operações rápidas */
#define DELAY_MEDIO     1562        /* 50ms - processamento médio */
#define DELAY_LONGO     3125        /* 100ms - processamento pesado */

/*==============================================================================
 * ESTRUTURAS E ENUMERAÇÕES
 *============================================================================*/

/**
 * @brief Algoritmos disponíveis para Zoom In (ampliação)
 */
typedef enum {
    ZOOM_IN_VIZINHO = 0,        /* Interpolação por vizinho mais próximo */
    ZOOM_IN_REPLICACAO,         /* Replicação simples de pixels */
    ZOOM_IN_NONE                /* Nenhum algoritmo selecionado */
} AlgoritmoZoomIn;

/**
 * @brief Algoritmos disponíveis para Zoom Out (redução)
 */
typedef enum {
    ZOOM_OUT_DECIMACAO = 0,     /* Decimação - amostragem de pixels */
    ZOOM_OUT_MEDIA,             /* Média de blocos - suavização */
    ZOOM_OUT_NONE               /* Nenhum algoritmo selecionado */
} AlgoritmoZoomOut;

/**
 * @brief Estrutura que define uma janela retangular na imagem
 */
typedef struct {
    int x_inicial;              /* Coordenada X do canto superior esquerdo */
    int y_inicial;              /* Coordenada Y do canto superior esquerdo */
    int x_final;                /* Coordenada X do canto inferior direito */
    int y_final;                /* Coordenada Y do canto inferior direito */
    int largura;                /* Largura da janela em pixels */
    int altura;                 /* Altura da janela em pixels */
    int ativa;                  /* Flag: 1 = janela ativa, 0 = inativa */
} Janela;

/**
 * @brief Estado global do sistema
 * Mantém todas as configurações e dados da sessão atual
 */
typedef struct {
    AlgoritmoZoomIn algoritmo_in;       /* Algoritmo de zoom in selecionado */
    AlgoritmoZoomOut algoritmo_out;     /* Algoritmo de zoom out selecionado */
    Janela janela;                      /* Configuração da janela ativa */
    int zoom_in_aplicado;               /* Flag: zoom in foi aplicado? */
    int vetor_original[TOTAL_PIXELS];   /* Buffer da imagem original */
    int vetor_processado[TOTAL_PIXELS]; /* Buffer da imagem processada */
} EstadoSistema;

/*==============================================================================
 * VARIÁVEIS GLOBAIS
 *============================================================================*/
static struct termios old_term, new_term;   /* Configurações do terminal */
static EstadoSistema estado;                /* Estado global do sistema */

/*==============================================================================
 * GERENCIAMENTO DO TERMINAL
 *============================================================================*/

/**
 * @brief Configura o terminal para modo não-canônico
 * 
 * Desabilita buffer de linha e echo, permitindo leitura
 * imediata de teclas individuais sem necessidade de Enter.
 */
void init_keyboard(void) {
    tcgetattr(0, &old_term);                /* Salva configurações originais */
    new_term = old_term;
    new_term.c_lflag &= ~(ICANON | ECHO);   /* Desabilita modo canônico e echo */
    tcsetattr(0, TCSANOW, &new_term);       /* Aplica novas configurações */
}

/**
 * @brief Restaura configurações originais do terminal
 * 
 * Deve ser chamado antes de encerrar o programa para
 * evitar deixar o terminal em estado inconsistente.
 */
void restore_keyboard(void) {
    tcsetattr(0, TCSANOW, &old_term);
}

/*==============================================================================
 * FUNÇÕES UTILITÁRIAS
 *============================================================================*/

/**
 * @brief Limita um valor dentro de um intervalo [min, max]
 * 
 * @param valor Valor a ser limitado
 * @param min   Valor mínimo permitido
 * @param max   Valor máximo permitido
 * @return      Valor limitado ao intervalo
 */
int clamp(int valor, int min, int max) {
    if (valor < min) return min;
    if (valor > max) return max;
    return valor;
}

/**
 * @brief Limpa a tela do terminal usando códigos ANSI
 */
void limpar_tela(void) {
    printf("\033[2J\033[H");    /* ANSI: limpa tela e move cursor para (0,0) */
    fflush(stdout);
}

/*==============================================================================
 * DEFINIÇÃO DE MENUS
 *============================================================================*/

/* Opções do menu principal quando nenhuma janela está selecionada */
const char *opcoes_menu_sem_janela[] = {
    "1 - Selecionar algoritmo ZOOM IN",
    "2 - Selecionar algoritmo ZOOM OUT",
    "3 - Selecionar janela",
    "4 - Enviar imagem para FPGA",
    "5 - Ler pixel especifico",
    "q - Sair"
};

/* Opções do menu principal quando uma janela está ativa */
const char *opcoes_menu_com_janela[] = {
    "1 - Selecionar algoritmo ZOOM IN",
    "2 - Selecionar algoritmo ZOOM OUT",
    "3 - Desativar janela",
    "4 - Enviar imagem para FPGA",
    "5 - Ler pixel especifico",
    "q - Sair"
};

const int NUM_OPCOES_PRINCIPAL = 6;

/* Opções do submenu de zoom in */
const char *opcoes_zoom_in[] = {
    "1 - Vizinho mais proximo",
    "2 - Replicacao de pixels",
    "3 - Nenhum (desativar)",
    "Voltar"
};
const int NUM_OPCOES_ZOOM_IN = 4;

/* Opções do submenu de zoom out */
const char *opcoes_zoom_out[] = {
    "1 - Decimacao",
    "2 - Media de blocos",
    "3 - Nenhum (desativar)",
    "Voltar"
};
const int NUM_OPCOES_ZOOM_OUT = 4;

/**
 * @brief Retorna o menu principal apropriado baseado no estado
 * 
 * @return Ponteiro para array de strings do menu (com ou sem janela)
 */
const char** obter_menu_principal(void) {
    if (estado.janela.ativa) {
        return opcoes_menu_com_janela;
    }
    return opcoes_menu_sem_janela;
}

/*==============================================================================
 * EXIBIÇÃO DE STATUS E MENUS
 *============================================================================*/

/**
 * @brief Exibe o status atual do sistema
 * 
 * Mostra os algoritmos selecionados e informações da janela (se ativa).
 */
void exibir_status(void) {
    printf("==================================\n");
    printf("         STATUS ATUAL\n");
    printf("==================================\n");

    /* Exibe algoritmo de zoom in selecionado */
    printf(" Zoom In: ");
    switch (estado.algoritmo_in) {
        case ZOOM_IN_VIZINHO:     printf("Vizinho mais proximo\n"); break;
        case ZOOM_IN_REPLICACAO:  printf("Replicacao de pixels\n"); break;
        case ZOOM_IN_NONE:        printf("Nenhum\n"); break;
    }

    /* Exibe algoritmo de zoom out selecionado */
    printf(" Zoom Out: ");
    switch (estado.algoritmo_out) {
        case ZOOM_OUT_DECIMACAO:  printf("Decimacao\n"); break;
        case ZOOM_OUT_MEDIA:      printf("Media de blocos\n"); break;
        case ZOOM_OUT_NONE:       printf("Nenhum\n"); break;
    }

    /* Exibe informações da janela se estiver ativa */
    printf(" Janela: ");
    if (estado.janela.ativa) {
        printf("(%d,%d) ate (%d,%d) [%dx%d]\n",
               estado.janela.x_inicial, estado.janela.y_inicial,
               estado.janela.x_final, estado.janela.y_final,
               estado.janela.largura, estado.janela.altura);
    } else {
        printf("Nenhuma\n");
    }

    printf("==================================\n");
}

/**
 * @brief Exibe um menu genérico com navegação por setas
 * 
 * @param titulo       Título do menu
 * @param opcoes       Array de strings com as opções
 * @param num_opcoes   Número total de opções
 * @param selecionada  Índice da opção atualmente selecionada
 */
void exibir_menu_generico(const char *titulo, const char **opcoes, int num_opcoes, int selecionada) {
    int i;
    limpar_tela();
    exibir_status();

    printf("\n==================================\n");
    printf("       %s\n", titulo);
    printf("==================================\n");
    printf(" SETAS: Navegar | BOTAO DIREITO: Confirmar\n");
    printf("==================================\n\n");

    /* Exibe todas as opções, destacando a selecionada */
    for (i = 0; i < num_opcoes; i++) {
        if (i == selecionada) {
            printf("  >>> [ %s ] <<<\n", opcoes[i]);
        } else {
            printf("      %s\n", opcoes[i]);
        }
    }
    
    printf("\n==================================\n");
    printf(" [+] Zoom In | [-] Zoom Out | [q] Sair\n");
    printf("==================================\n");
    fflush(stdout);
}

/*==============================================================================
 * ENTRADA DO MOUSE
 *============================================================================*/

/**
 * @brief Permite ao usuário selecionar uma coordenada usando o mouse
 * 
 * O usuário move o mouse para ajustar as coordenadas X e Y,
 * e confirma com o botão direito.
 * 
 * @param fd_mouse  File descriptor do dispositivo de mouse
 * @param out_x     Ponteiro para armazenar coordenada X selecionada
 * @param out_y     Ponteiro para armazenar coordenada Y selecionada
 * @param x_max     Valor máximo permitido para X
 * @param y_max     Valor máximo permitido para Y
 */
void selecionar_coordenada_mouse(int fd_mouse, int *out_x, int *out_y, int x_max, int y_max) {
    struct input_event ev;
    int x = x_max / 2, y = y_max / 2;   /* Inicia no centro */
    int confirmado = 0;

    printf("\n>>> Mova o mouse para selecionar a coordenada.\n");
    printf(">>> Pressione BOTAO DIREITO para confirmar.\n\n");

    while (!confirmado) {
        if (read(fd_mouse, &ev, sizeof(ev)) > 0) {
            /* Processa eventos de movimento do mouse */
            if (ev.type == EV_REL) {
                if (ev.code == REL_X) x += ev.value;    /* Movimento horizontal */
                if (ev.code == REL_Y) y += ev.value;    /* Movimento vertical */

                /* Limita coordenadas aos valores máximos */
                x = clamp(x, 0, x_max);
                y = clamp(y, 0, y_max);

                /* Atualiza exibição em tempo real */
                printf("\r    Coordenada: X = %3d  |  Y = %3d      ", x, y);
                fflush(stdout);
            }

            /* Detecta clique do botão direito */
            if (ev.type == EV_KEY && ev.code == BTN_RIGHT && ev.value == 1) {
                confirmado = 1;
                printf("\n\n>>> CONFIRMADO: X = %d, Y = %d\n", x, y);
            }
        }
    }

    *out_x = x;
    *out_y = y;
}

/*==============================================================================
 * GERENCIAMENTO DE JANELA
 *============================================================================*/

/**
 * @brief Permite ao usuário selecionar uma janela retangular
 * 
 * O usuário seleciona dois pontos (inicial e final) usando o mouse.
 * A janela é validada para garantir tamanho máximo de 100x100 pixels.
 * 
 * @param fd_mouse  File descriptor do dispositivo de mouse
 * @return          1 se a janela foi selecionada com sucesso, 0 caso contrário
 */
int selecionar_janela(int fd_mouse) {
    int x0, y0, xf, yf;
    int largura, altura;

    printf("\n=== SELECAO DE JANELA ===\n");
    printf("A janela deve ter no maximo %dx%d pixels.\n\n", MAX_WINDOW_SIZE, MAX_WINDOW_SIZE);

    /* Seleciona ponto inicial */
    printf("-- Selecione o ponto INICIAL --\n");
    selecionar_coordenada_mouse(fd_mouse, &x0, &y0, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1);

    /* Seleciona ponto final */
    printf("\n-- Selecione o ponto FINAL --\n");
    selecionar_coordenada_mouse(fd_mouse, &xf, &yf, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1);

    /* Normaliza coordenadas (garante que inicial < final) */
    if (x0 > xf) { int t = x0; x0 = xf; xf = t; }
    if (y0 > yf) { int t = y0; y0 = yf; yf = t; }

    /* Calcula dimensões */
    largura = xf - x0 + 1;
    altura = yf - y0 + 1;

    /* Valida tamanho da janela */
    if (largura > MAX_WINDOW_SIZE || altura > MAX_WINDOW_SIZE) {
        printf("\nErro: A janela deve ser no maximo %dx%d!\n", MAX_WINDOW_SIZE, MAX_WINDOW_SIZE);
        printf("Sua janela: %dx%d\n", largura, altura);
        return 0;
    }

    /* Armazena configuração da janela no estado global */
    estado.janela.x_inicial = x0;
    estado.janela.y_inicial = y0;
    estado.janela.x_final = xf;
    estado.janela.y_final = yf;
    estado.janela.largura = largura;
    estado.janela.altura = altura;
    estado.janela.ativa = 1;
    estado.zoom_in_aplicado = 0;

    printf("\n>>> Janela selecionada: (%d,%d) ate (%d,%d) [%dx%d]\n",
           x0, y0, xf, yf, largura, altura);

    return 1;
}

/**
 * @brief Desativa a janela atual e limpa suas configurações
 */
void desativar_janela(void) {
    estado.janela.ativa = 0;
    estado.janela.x_inicial = 0;
    estado.janela.y_inicial = 0;
    estado.janela.x_final = 0;
    estado.janela.y_final = 0;
    estado.janela.largura = 0;
    estado.janela.altura = 0;
    estado.zoom_in_aplicado = 0;

    printf("\n>>> Janela desativada!\n");
}

/*==============================================================================
 * OPERAÇÕES DE ZOOM
 *============================================================================*/

/**
 * @brief Carrega a imagem original da memória da FPGA para o buffer
 * 
 * Lê todos os 76800 pixels da memória 0 (imagem original) e
 * armazena no vetor_original.
 */
void carregar_imagem_original(void) {
    int i;
    printf("Carregando imagem original da memoria...\n");
    for (i = 0; i < TOTAL_PIXELS; i++) {
        estado.vetor_original[i] = carregar_pixel(i, 0);
    }
    printf("Imagem carregada.\n");
}

/**
 * @brief Renderiza o resultado do zoom in na janela
 * 
 * Combina a imagem original com a região processada,
 * mapeando pixels da área ampliada de volta para a janela original.
 */
void render_zoom_in_result(void) {
    int i;
    int x, y, rel_x, rel_y, fonte_x, fonte_y, endereco_fonte;
    int offset_x, offset_y;

    /* Calcula offset para centralizar a ampliação */
    offset_x = estado.janela.largura / 2;
    offset_y = estado.janela.altura / 2;

    for (i = 0; i < TOTAL_PIXELS; i++) {
        x = i % SCREEN_WIDTH;
        y = i / SCREEN_WIDTH;

        /* Verifica se o pixel está dentro da janela */
        if (x >= estado.janela.x_inicial && x <= estado.janela.x_final &&
            y >= estado.janela.y_inicial && y <= estado.janela.y_final) {

            /* Calcula coordenadas relativas à janela */
            rel_x = x - estado.janela.x_inicial;
            rel_y = y - estado.janela.y_inicial;
            
            /* Mapeia para a imagem ampliada */
            fonte_x = offset_x + rel_x;
            fonte_y = offset_y + rel_y;
            endereco_fonte = fonte_y * SCREEN_WIDTH + fonte_x;

            /* Usa pixel processado se disponível, senão usa original */
            if (endereco_fonte < TOTAL_PIXELS && estado.vetor_processado[endereco_fonte] != 0x000000) {
                enviar_pixel(estado.vetor_processado[endereco_fonte], i);
            } else {
                enviar_pixel(estado.vetor_original[i], i);
            }
        } else {
            /* Fora da janela: usa imagem original */
            enviar_pixel(estado.vetor_original[i], i);
        }
    }
}

/**
 * @brief Reaplica o zoom in na janela (usado no modo interativo)
 * 
 * Versão otimizada para atualizações rápidas durante movimentação
 * da janela em tempo real.
 */
void reaplicar_zoom_in_janela_interativo(void) {
    int i;
    int x, y;
    int vetor_auxiliar[TOTAL_PIXELS];

    /* Desliga display temporariamente para evitar flickering */
    controle_imagem(1);
    usleep(DELAY_CURTO);
    controle_imagem(0);    /* Liga display */

    estado.zoom_in_aplicado = 0;
    printf(">>> Zoom Out aplicado com sucesso!\n");
}

/**
 * @brief Aplica zoom in globalmente (na imagem inteira)
 * 
 * O usuário seleciona um ponto de âncora que será o centro
 * da ampliação. A imagem inteira é processada.
 * 
 * @param fd_mouse  File descriptor do dispositivo de mouse
 * @return          1 se o zoom foi aplicado, 0 caso contrário
 */
int aplicar_zoom_in_global(int fd_mouse) {
    int x_anchor = 0, y_anchor = 0;

    /* Validações */
    if (estado.algoritmo_in == ZOOM_IN_NONE) {
        printf("Erro: Nenhum algoritmo de Zoom In selecionado!\n");
        return 0;
    }
    if (estado.zoom_in_aplicado) {
        printf("Erro: Zoom In ja foi aplicado! Use Zoom Out primeiro.\n");
        return 0;
    }

    printf("\n=== APLICANDO ZOOM IN GLOBAL ===\n");
    printf("Selecione a coordenada de origem (max X=159, Y=119)\n");
    
    /* Seleciona ponto de âncora (limites reduzidos para zoom 2x) */
    selecionar_coordenada_mouse(fd_mouse, &x_anchor, &y_anchor, 159, 119);

    /* Aplica algoritmo selecionado */
    printf("Aplicando algoritmo: ");
    switch (estado.algoritmo_in) {
        case ZOOM_IN_VIZINHO:
            printf("Vizinho mais proximo\n");
            vizinho_mais_proximo(x_anchor, y_anchor);
            break;
        case ZOOM_IN_REPLICACAO:
            printf("Replicacao de pixels\n");
            replicacao_pixel(x_anchor, y_anchor);
            break;
        default:
            controle_imagem(0);
            return 0;
    }

    estado.zoom_in_aplicado = 1;
    printf(">>> Zoom In GLOBAL aplicado com sucesso!\n");
    return 1;
}

/**
 * @brief Aplica zoom out globalmente (na imagem inteira)
 * 
 * Reduz a imagem ampliada de volta ao tamanho original.
 */
void aplicar_zoom_out_global(void) {
    /* Validações */
    if (!estado.zoom_in_aplicado) {
        printf("Erro: Voce deve aplicar Zoom In primeiro!\n");
        return;
    }
    if (estado.algoritmo_out == ZOOM_OUT_NONE) {
        printf("Erro: Nenhum algoritmo de Zoom Out selecionado!\n");
        return;
    }

    printf("\n=== APLICANDO ZOOM OUT GLOBAL ===\n");

    /* Aplica algoritmo selecionado */
    printf("Aplicando algoritmo: ");
    switch (estado.algoritmo_out) {
        case ZOOM_OUT_DECIMACAO:
            printf("Decimacao\n");
            decimacao();
            break;
        case ZOOM_OUT_MEDIA:
            printf("Media de blocos\n");
            media_de_blocos();
            break;
        default:
            controle_imagem(0);
            return;
    }

    estado.zoom_in_aplicado = 0;
    printf(">>> Zoom Out GLOBAL aplicado com sucesso!\n");
}

/**
 * @brief Modo interativo: permite mover a janela em tempo real
 * 
 * O usuário pode usar as setas do teclado para mover a janela
 * e ver o resultado do zoom em diferentes regiões da imagem.
 * 
 * Controles:
 *   - Setas: movem a janela
 *   - +/-: ajustam velocidade de movimento
 *   - q: sair do modo interativo
 */
void modo_janela_interativo(void) {
    int sair = 0;
    int pos_x, pos_y;
    int passo = 1;    /* Velocidade de movimento em pixels */

    /* Validações */
    if (!estado.janela.ativa) {
        printf("Erro: Selecione uma janela primeiro!\n");
        return;
    }

    if (!estado.zoom_in_aplicado) {
        printf("Erro: Aplique Zoom In primeiro para entrar no modo interativo!\n");
        return;
    }

    printf("\n=== MODO JANELA INTERATIVO (TECLAS) ===\n");
    printf("Setas: mover janela | +/- ajusta velocidade | q: sair\n");

    /* Posição inicial da janela */
    pos_x = estado.janela.x_inicial;
    pos_y = estado.janela.y_inicial;

    while (!sair) {
        int c = getchar();

        /* Detecta sequências de escape (setas) */
        if (c == 27) {
            char s1 = getchar();
            if (s1 == '[') {
                char s2 = getchar();
                int nova_x = pos_x;
                int nova_y = pos_y;
                
                /* Processa direção da seta */
                if (s2 == 'A') {          /* Seta para cima */
                    nova_y -= passo;
                } else if (s2 == 'B') {   /* Seta para baixo */
                    nova_y += passo;
                } else if (s2 == 'C') {   /* Seta para direita */
                    nova_x += passo;
                } else if (s2 == 'D') {   /* Seta para esquerda */
                    nova_x -= passo;
                }
                
                /* Limita coordenadas para manter janela dentro da tela */
                nova_x = clamp(nova_x, 0, SCREEN_WIDTH - estado.janela.largura);
                nova_y = clamp(nova_y, 0, SCREEN_HEIGHT - estado.janela.altura);

                /* Se houve movimento, atualiza janela */
                if (nova_x != pos_x || nova_y != pos_y) {
                    pos_x = nova_x;
                    pos_y = nova_y;

                    /* Atualiza estado da janela */
                    estado.janela.x_inicial = pos_x;
                    estado.janela.y_inicial = pos_y;
                    estado.janela.x_final = pos_x + estado.janela.largura - 1;
                    estado.janela.y_final = pos_y + estado.janela.altura - 1;

                    /* Reaplica zoom na nova posição */
                    reaplicar_zoom_in_janela_interativo();

                    /* Atualiza feedback visual */
                    printf("\r Janela: (%3d, %3d) ate (%3d, %3d)  passo=%d   ",
                           estado.janela.x_inicial, estado.janela.y_inicial,
                           estado.janela.x_final, estado.janela.y_final, passo);
                    fflush(stdout);
                }
            }
        } 
        /* Aumenta velocidade */
        else if (c == '+' || c == '=') {
            if (passo < 20) passo++;
            printf("\r Velocidade (passo) = %d   ", passo);
            fflush(stdout);
        } 
        /* Diminui velocidade */
        else if (c == '-' || c == '_') {
            if (passo > 1) passo--;
            printf("\r Velocidade (passo) = %d   ", passo);
            fflush(stdout);
        } 
        /* Sair */
        else if (c == 'q' || c == 'Q') {
            sair = 1;
            printf("\n>>> Saindo do modo janela.\n");
        }
    }
}

/*==============================================================================
 * NAVEGAÇÃO DE MENUS
 *============================================================================*/

/**
 * @brief Gerencia navegação em um menu usando mouse e teclado
 * 
 * Permite navegação com setas do teclado, confirmação com botão
 * direito do mouse, e atalhos para zoom (+/-) disponíveis a qualquer momento.
 * 
 * @param fd_mouse      File descriptor do mouse
 * @param titulo        Título do menu
 * @param opcoes        Array de strings com opções
 * @param num_opcoes    Número de opções
 * @param opcao_atual   Opção inicialmente selecionada
 * @return              Índice da opção confirmada
 */
int navegar_menu(int fd_mouse, const char *titulo, const char **opcoes, int num_opcoes, int opcao_atual) {
    struct input_event ev;
    fd_set fds;
    int confirmado = 0;

    exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);

    while (!confirmado) {
        FD_ZERO(&fds);
        FD_SET(fd_mouse, &fds);   /* Monitora mouse */
        FD_SET(0, &fds);          /* Monitora teclado (stdin) */

        {
            int maxfd = fd_mouse > 0 ? fd_mouse : 0;

            /* Aguarda entrada do mouse ou teclado */
            select(maxfd + 1, &fds, NULL, NULL, NULL);

            /* Processa eventos do mouse */
            if (FD_ISSET(fd_mouse, &fds)) {
                if (read(fd_mouse, &ev, sizeof(ev)) > 0) {
                    /* Botão direito confirma seleção */
                    if (ev.type == EV_KEY && ev.code == BTN_RIGHT && ev.value == 1) {
                        confirmado = 1;
                        printf("\n>>> Opcao confirmada: %s\n", opcoes[opcao_atual]);
                    }
                }
            }

            /* Processa eventos do teclado */
            if (FD_ISSET(0, &fds)) {
                char c = getchar();

                /* Detecta sequências de escape (setas) */
                if (c == 27) {
                    char seq1 = getchar();
                    if (seq1 == '[') {
                        char seq2 = getchar();
                        
                        /* Seta para cima: opção anterior */
                        if (seq2 == 'A') {
                            opcao_atual--;
                            if (opcao_atual < 0) opcao_atual = num_opcoes - 1;
                            exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);
                        } 
                        /* Seta para baixo: próxima opção */
                        else if (seq2 == 'B') {
                            opcao_atual++;
                            if (opcao_atual >= num_opcoes) opcao_atual = 0;
                            exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);
                        }
                    }
                } 
                /* Atalho: aplicar zoom in */
                else if (c == '+' || c == '=') {
                    if (estado.janela.ativa) {
                        /* Modo janela: aplica zoom e entra em modo interativo */
                        if (aplicar_zoom_in_janela()) {
                            printf("\n>>> Entrando no modo interativo (teclas)...\n");
                            printf("Pressione qualquer tecla para continuar...\n");
                            getchar();
                            modo_janela_interativo();
                        } else {
                            printf("\nPressione qualquer tecla para continuar...\n");
                            getchar();
                        }
                    } else {
                        /* Modo global */
                        aplicar_zoom_in_global(fd_mouse);
                        printf("\nPressione qualquer tecla para continuar...\n");
                        getchar();
                    }
                    exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);
                } 
                /* Atalho: aplicar zoom out */
                else if (c == '-' || c == '_') {
                    if (estado.janela.ativa) {
                        aplicar_zoom_out_janela();
                    } else {
                        aplicar_zoom_out_global();
                    }
                    printf("\nPressione qualquer tecla para continuar...\n");
                    getchar();
                    exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);
                }
            }
        }
    }

    return opcao_atual;
}

/**
 * @brief Menu para seleção de algoritmo de Zoom In
 * 
 * @param fd_mouse  File descriptor do mouse
 */
void menu_zoom_in(int fd_mouse) {
    int opcao = navegar_menu(fd_mouse, "ALGORITMOS ZOOM IN", opcoes_zoom_in, NUM_OPCOES_ZOOM_IN, 0);

    switch (opcao) {
        case 0:
            estado.algoritmo_in = ZOOM_IN_VIZINHO;
            printf(">>> Algoritmo selecionado: Vizinho mais proximo\n");
            break;
        case 1:
            estado.algoritmo_in = ZOOM_IN_REPLICACAO;
            printf(">>> Algoritmo selecionado: Replicacao de pixels\n");
            break;
        case 2:
            estado.algoritmo_in = ZOOM_IN_NONE;
            printf(">>> Zoom In desativado\n");
            break;
        case 3:
            /* Voltar - não faz nada */
            break;
    }
}

/**
 * @brief Menu para seleção de algoritmo de Zoom Out
 * 
 * @param fd_mouse  File descriptor do mouse
 */
void menu_zoom_out(int fd_mouse) {
    int opcao = navegar_menu(fd_mouse, "ALGORITMOS ZOOM OUT", opcoes_zoom_out, NUM_OPCOES_ZOOM_OUT, 0);

    switch (opcao) {
        case 0:
            estado.algoritmo_out = ZOOM_OUT_DECIMACAO;
            printf(">>> Algoritmo selecionado: Decimacao\n");
            break;
        case 1:
            estado.algoritmo_out = ZOOM_OUT_MEDIA;
            printf(">>> Algoritmo selecionado: Media de blocos\n");
            break;
        case 2:
            estado.algoritmo_out = ZOOM_OUT_NONE;
            printf(">>> Zoom Out desativado\n");
            break;
        case 3:
            /* Voltar - não faz nada */
            break;
    }
}

/**
 * @brief Inicializa o estado do sistema com valores padrão
 */
void inicializar_estado(void) {
    estado.algoritmo_in = ZOOM_IN_NONE;
    estado.algoritmo_out = ZOOM_OUT_NONE;
    estado.janela.ativa = 0;
    estado.janela.x_inicial = 0;
    estado.janela.y_inicial = 0;
    estado.janela.x_final = 0;
    estado.janela.y_final = 0;
    estado.janela.largura = 0;
    estado.janela.altura = 0;
    estado.zoom_in_aplicado = 0;
    memset(estado.vetor_original, 0, sizeof(estado.vetor_original));
    memset(estado.vetor_processado, 0, sizeof(estado.vetor_processado));
}

/*==============================================================================
 * FUNÇÃO PRINCIPAL
 *============================================================================*/

/**
 * @brief Ponto de entrada do programa
 * 
 * Inicializa hardware, configura terminal, e executa loop principal
 * do menu interativo.
 * 
 * @return 0 em caso de sucesso, 1 em caso de erro
 */
int main(void) {
    const char *mouse_dev = "/dev/input/event0";
    int fd_mouse;
    int opcao_atual = 0;

    /* Abre dispositivo de mouse */
    fd_mouse = open(mouse_dev, O_RDONLY);
    if (fd_mouse < 0) {
        perror("Erro ao abrir mouse");
        return 1;
    }

    printf("Inicializando sistema...\n");
    inicializar_estado();

    /* Mapeia endereços da FPGA */
    printf("Mapeando enderecos...\n");
    mapear_enderecos();
    printf("Enderecos mapeados com sucesso.\n");

    /* Configura terminal para modo não-canônico */
    init_keyboard();

    printf("\n>>> Sistema pronto! Use as setas e botao direito do mouse.\n");
    printf(">>> Use [+] para Zoom In e [-] para Zoom Out a qualquer momento.\n\n");

    /* Loop principal do menu */
    while (1) {
        const char **menu_atual = obter_menu_principal();
        opcao_atual = navegar_menu(fd_mouse, "MENU PRINCIPAL",
                                   menu_atual, NUM_OPCOES_PRINCIPAL, opcao_atual);

        switch (opcao_atual) {
            /* Opção 1: Selecionar algoritmo Zoom In */
            case 0:
                menu_zoom_in(fd_mouse);
                break;

            /* Opção 2: Selecionar algoritmo Zoom Out */
            case 1:
                menu_zoom_out(fd_mouse);
                break;

            /* Opção 3: Selecionar/Desativar janela */
            case 2:
                if (estado.janela.ativa) {
                    desativar_janela();
                } else {
                    if (selecionar_janela(fd_mouse)) {
                        carregar_imagem_original();
                        printf("\n>>> Janela configurada! Use [+] para aplicar Zoom In.\n");
                    }
                }
                break;

            /* Opção 4: Enviar imagem para FPGA */
            case 3:
                printf("\n=== ENVIANDO IMAGEM PARA FPGA ===\n");
                printf("Carregando e enviando imagem...\n");
                enviar_imagem_fpga("talarelo.pgm");
                carregar_imagem_original();
                printf(">>> Imagem enviada com sucesso!\n");
                break;

            /* Opção 5: Ler pixel específico */
            case 4:
            {
                int x_read, y_read;
                int endereco;
                int pixel;

                printf("\n=== LER PIXEL ESPECIFICO ===\n");
                selecionar_coordenada_mouse(fd_mouse, &x_read, &y_read,
                                            SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1);
                endereco = y_read * SCREEN_WIDTH + x_read;
                printf("Lendo pixel...\n");
                pixel = carregar_pixel(endereco, 1);
                printf("\n>>> Pixel em (%d, %d): 0x%02X (decimal: %d)\n",
                       x_read, y_read, pixel, pixel);
                break;
            }

            /* Opção q: Sair */
            case 5:
                printf("\nSaindo do programa...\n");
                goto cleanup;
        }

        printf("\nPressione qualquer tecla para voltar ao menu...\n");
        getchar();
    }

cleanup:
    /* Limpeza de recursos */
    restore_keyboard();
    close(fd_mouse);
    fechar_enderecos();
    return 0;
}TO);

    /* Prepara imagem auxiliar: apenas região da janela */
    for (i = 0; i < TOTAL_PIXELS; i++) {
        x = i % SCREEN_WIDTH;
        y = i / SCREEN_WIDTH;

        if (x >= estado.janela.x_inicial && x <= estado.janela.x_final &&
            y >= estado.janela.y_inicial && y <= estado.janela.y_final) {
            vetor_auxiliar[i] = estado.vetor_original[i];
        } else {
            vetor_auxiliar[i] = 0x000000;   /* Preto fora da janela */
        }
    }
    
    /* Envia imagem preparada para FPGA */
    for (i = 0; i < TOTAL_PIXELS; i++) {
        enviar_pixel(vetor_auxiliar[i], i);
    }

    usleep(DELAY_MEDIO);

    /* Aplica algoritmo de zoom selecionado */
    switch (estado.algoritmo_in) {
        case ZOOM_IN_VIZINHO:
            vizinho_mais_proximo(estado.janela.x_inicial, estado.janela.y_inicial);
            break;
        case ZOOM_IN_REPLICACAO:
            replicacao_pixel(estado.janela.x_inicial, estado.janela.y_inicial);
            break;
        default:
            controle_imagem(0);
            return;
    }

    usleep(DELAY_LONGO);

    /* Carrega resultado processado */
    for (i = 0; i < TOTAL_PIXELS; i++) {
        estado.vetor_processado[i] = carregar_pixel(i, 1);
    }
    
    /* Renderiza resultado final */
    render_zoom_in_result();

    usleep(DELAY_CURTO);
    controle_imagem(0);    /* Liga display novamente */
}

/**
 * @brief Aplica zoom in na janela selecionada
 * 
 * Processo completo:
 * 1. Valida pré-condições (janela ativa, algoritmo selecionado)
 * 2. Prepara imagem com apenas a região da janela
 * 3. Envia para FPGA e aplica algoritmo de zoom
 * 4. Recupera resultado e renderiza na tela
 * 
 * @return 1 se o zoom foi aplicado com sucesso, 0 caso contrário
 */
int aplicar_zoom_in_janela(void) {
    int i;
    int x, y;
    int vetor_auxiliar[TOTAL_PIXELS];

    /* Validações */
    if (!estado.janela.ativa) {
        printf("Erro: Nenhuma janela selecionada!\n");
        return 0;
    }

    if (estado.algoritmo_in == ZOOM_IN_NONE) {
        printf("Erro: Nenhum algoritmo de Zoom In selecionado!\n");
        return 0;
    }

    if (estado.zoom_in_aplicado) {
        printf("Erro: Zoom In ja foi aplicado! Use Zoom Out primeiro.\n");
        return 0;
    }

    printf("\n=== APLICANDO ZOOM IN NA JANELA ===\n");

    /* Desliga display durante processamento */
    controle_imagem(1);
    usleep(DELAY_CURTO);

    /* Prepara imagem: extrai apenas a janela */
    for (i = 0; i < TOTAL_PIXELS; i++) {
        x = i % SCREEN_WIDTH;
        y = i / SCREEN_WIDTH;

        if (x >= estado.janela.x_inicial && x <= estado.janela.x_final &&
            y >= estado.janela.y_inicial && y <= estado.janela.y_final) {
            vetor_auxiliar[i] = estado.vetor_original[i];
        } else {
            vetor_auxiliar[i] = 0x000000;
        }
    }

    /* Envia para FPGA */
    for (i = 0; i < TOTAL_PIXELS; i++) {
        enviar_pixel(vetor_auxiliar[i], i);
    }

    usleep(DELAY_MEDIO);

    /* Aplica algoritmo selecionado */
    printf("Aplicando algoritmo: ");
    switch (estado.algoritmo_in) {
        case ZOOM_IN_VIZINHO:
            printf("Vizinho mais proximo\n");
            vizinho_mais_proximo(estado.janela.x_inicial, estado.janela.y_inicial);
            break;
        case ZOOM_IN_REPLICACAO:
            printf("Replicacao de pixels\n");
            replicacao_pixel(estado.janela.x_inicial, estado.janela.y_inicial);
            break;
        default:
            controle_imagem(0);
            return 0;
    }

    usleep(DELAY_LONGO);

    /* Recupera resultado do processamento */
    for (i = 0; i < TOTAL_PIXELS; i++) {
        estado.vetor_processado[i] = carregar_pixel(i, 1);
    }

    /* Renderiza resultado combinado */
    render_zoom_in_result();

    usleep(DELAY_CURTO);
    controle_imagem(0);    /* Liga display */

    estado.zoom_in_aplicado = 1;

    printf(">>> Zoom In aplicado com sucesso!\n");
    return 1;
}

void aplicar_zoom_out_janela(void) {
    int i;
    int x, y, rel_x, rel_y, fonte_x, fonte_y, endereco_fonte;
    int min_x, max_x, min_y, max_y;
    int vetor_resultado[TOTAL_PIXELS];

    if (!estado.janela.ativa) {
        printf("Erro: Nenhuma janela selecionada!\n");
        return;
    }

    if (! estado.zoom_in_aplicado) {
        printf("Erro: Voce deve aplicar Zoom In primeiro!\n");
        return;
    }

    if (estado.algoritmo_out == ZOOM_OUT_NONE) {
        printf("Erro: Nenhum algoritmo de Zoom Out selecionado!\n");
        return;
    }

    printf("\n=== APLICANDO ZOOM OUT NA JANELA ===\n");

    controle_imagem(1);
    usleep(DELAY_CURTO);

    for (i = 0; i < TOTAL_PIXELS; i++) {
        enviar_pixel(estado.vetor_processado[i], i);
    }

    usleep(DELAY_MEDIO);

    printf("Aplicando algoritmo: ");
    switch (estado.algoritmo_out) {
        case ZOOM_OUT_DECIMACAO:
            printf("Decimacao\n");
            decimacao();
            break;
        case ZOOM_OUT_MEDIA:
            printf("Media de blocos\n");
            media_de_blocos();
            break;
        default:
            controle_imagem(0);
            return;
    }

    usleep(DELAY_LONGO);

    for (i = 0; i < TOTAL_PIXELS; i++) {
        vetor_resultado[i] = carregar_pixel(i, 1);
    }

    min_x = SCREEN_WIDTH; max_x = 0; min_y = SCREEN_HEIGHT; max_y = 0;
    for (i = 0; i < TOTAL_PIXELS; i++) {
        if (vetor_resultado[i] != 0x000000) {
            x = i % SCREEN_WIDTH;
            y = i / SCREEN_WIDTH;
            if (x < min_x) min_x = x;
            if (x > max_x) max_x = x;
            if (y < min_y) min_y = y;
            if (y > max_y) max_y = y;
        }
    }

    for (i = 0; i < TOTAL_PIXELS; i++) {
        x = i % SCREEN_WIDTH;
        y = i / SCREEN_WIDTH;

        if (x >= estado.janela. x_inicial && x <= estado.janela.x_final - 1 &&
            y >= estado. janela.y_inicial && y <= estado.janela.y_final) {

            rel_x = x - estado.janela.x_inicial;
            rel_y = y - estado.janela.y_inicial;
            fonte_x = min_x + 1 + rel_x;
            fonte_y = min_y + rel_y;
            endereco_fonte = fonte_y * SCREEN_WIDTH + fonte_x;

            if (endereco_fonte < TOTAL_PIXELS && vetor_resultado[endereco_fonte] != 0x000000) {
                enviar_pixel(vetor_resultado[endereco_fonte], i);
            } else {
                enviar_pixel(estado. vetor_original[i], i);
            }
        } else {
            enviar_pixel(estado.vetor_original[i], i);
        }
    }

    usleep(DELAY_CURTO);
    controle_imagem(0);

    estado.zoom_in_aplicado = 0;
    printf(">>> Zoom Out aplicado com sucesso!\n");
}

int aplicar_zoom_in_global(int fd_mouse) {
    int x_anchor = 0, y_anchor = 0;

    if (estado.algoritmo_in == ZOOM_IN_NONE) {
        printf("Erro: Nenhum algoritmo de Zoom In selecionado!\n");
        return 0;
    }
    if (estado. zoom_in_aplicado) {
        printf("Erro: Zoom In ja foi aplicado! Use Zoom Out primeiro.\n");
        return 0;
    }

    printf("\n=== APLICANDO ZOOM IN GLOBAL ===\n");
    printf("Selecione a coordenada de origem (max X=159, Y=119)\n");
    selecionar_coordenada_mouse(fd_mouse, &x_anchor, &y_anchor, 159, 119);


    printf("Aplicando algoritmo: ");
    switch (estado.algoritmo_in) {
        case ZOOM_IN_VIZINHO:
            printf("Vizinho mais proximo\n");
            vizinho_mais_proximo(x_anchor, y_anchor);
            break;
        case ZOOM_IN_REPLICACAO:
            printf("Replicacao de pixels\n");
            replicacao_pixel(x_anchor, y_anchor);
            break;
        default:
            controle_imagem(0);
            return 0;
    }


    estado.zoom_in_aplicado = 1;
    printf(">>> Zoom In GLOBAL aplicado com sucesso!\n");
    return 1;
}

/**
 * @brief Aplica zoom out na janela ampliada
 * 
 * Reduz a imagem ampliada de volta ao tamanho original,
 * reposicionando o resultado na área da janela.
 */
void aplicar_zoom_out_janela(void) {
    int i;
    int x, y, rel_x, rel_y, fonte_x, fonte_y, endereco_fonte;
    int min_x, max_x, min_y, max_y;
    int vetor_resultado[TOTAL_PIXELS];

    /* Validações de pré-condições */
    if (!estado.janela.ativa) {
        printf("Erro: Nenhuma janela selecionada!\n");
        return;
    }

    if (!estado.zoom_in_aplicado) {
        printf("Erro: Voce deve aplicar Zoom In primeiro!\n");
        return;
    }

    if (estado.algoritmo_out == ZOOM_OUT_NONE) {
        printf("Erro: Nenhum algoritmo de Zoom Out selecionado!\n");
        return;
    }

    printf("\n=== APLICANDO ZOOM OUT NA JANELA ===\n");

    /* Desliga display temporariamente */
    controle_imagem(1);
    usleep(DELAY_CURTO);

    /* Envia imagem processada (ampliada) para FPGA */
    for (i = 0; i < TOTAL_PIXELS; i++) {
        enviar_pixel(estado.vetor_processado[i], i);
    }

    usleep(DELAY_MEDIO);

    /* Aplica algoritmo de zoom out selecionado */
    printf("Aplicando algoritmo: ");
    switch (estado.algoritmo_out) {
        case ZOOM_OUT_DECIMACAO:
            printf("Decimacao\n");
            decimacao();
            break;
        case ZOOM_OUT_MEDIA:
            printf("Media de blocos\n");
            media_de_blocos();
            break;
        default:
            controle_imagem(0);
            return;
    }

    usleep(DELAY_LONGO);

    /* Recupera resultado do processamento */
    for (i = 0; i < TOTAL_PIXELS; i++) {
        vetor_resultado[i] = carregar_pixel(i, 1);
    }

    /* Encontra limites da região não-preta (região válida após zoom out) */
    min_x = SCREEN_WIDTH; 
    max_x = 0; 
    min_y = SCREEN_HEIGHT; 
    max_y = 0;
    
    for (i = 0; i < TOTAL_PIXELS; i++) {
        if (vetor_resultado[i] != 0x000000) {
            x = i % SCREEN_WIDTH;
            y = i / SCREEN_WIDTH;
            if (x < min_x) min_x = x;
            if (x > max_x) max_x = x;
            if (y < min_y) min_y = y;
            if (y > max_y) max_y = y;
        }
    }

    /* Mapeia resultado de volta para a janela original */
    for (i = 0; i < TOTAL_PIXELS; i++) {
        x = i % SCREEN_WIDTH;
        y = i / SCREEN_WIDTH;

        /* Verifica se pixel está dentro da janela */
        if (x >= estado.janela.x_inicial && x <= estado.janela.x_final - 1 &&
            y >= estado.janela.y_inicial && y <= estado.janela.y_final) {

            /* Calcula coordenadas relativas à janela */
            rel_x = x - estado.janela.x_inicial;
            rel_y = y - estado.janela.y_inicial;
            
            /* Mapeia para a região reduzida */
            fonte_x = min_x + 1 + rel_x;
            fonte_y = min_y + rel_y;
            endereco_fonte = fonte_y * SCREEN_WIDTH + fonte_x;

            /* Usa pixel reduzido se disponível, senão usa original */
            if (endereco_fonte < TOTAL_PIXELS && vetor_resultado[endereco_fonte] != 0x000000) {
                enviar_pixel(vetor_resultado[endereco_fonte], i);
            } else {
                enviar_pixel(estado.vetor_original[i], i);
            }
        } else {
            /* Fora da janela: restaura imagem original */
            enviar_pixel(estado.vetor_original[i], i);
        }
    }

    usleep(DELAY_CURTO);
    controle_imagem(0);    /* Liga display novamente */

    estado.zoom_in_aplicado = 0;
    printf(">>> Zoom Out aplicado com sucesso!\n");
}

/**
 * @brief Aplica zoom in globalmente (na imagem inteira)
 * 
 * O usuário seleciona um ponto de âncora que será o centro
 * da ampliação. A imagem inteira é processada pelo coprocessador.
 * 
 * @param fd_mouse  File descriptor do dispositivo de mouse
 * @return          1 se o zoom foi aplicado com sucesso, 0 caso contrário
 */
int aplicar_zoom_in_global(int fd_mouse) {
    int x_anchor = 0, y_anchor = 0;

    /* Validações de pré-condições */
    if (estado.algoritmo_in == ZOOM_IN_NONE) {
        printf("Erro: Nenhum algoritmo de Zoom In selecionado!\n");
        return 0;
    }
    if (estado.zoom_in_aplicado) {
        printf("Erro: Zoom In ja foi aplicado! Use Zoom Out primeiro.\n");
        return 0;
    }

    printf("\n=== APLICANDO ZOOM IN GLOBAL ===\n");
    printf("Selecione a coordenada de origem (max X=159, Y=119)\n");
    
    /* Seleciona ponto de âncora (limites reduzidos para zoom 2x) */
    selecionar_coordenada_mouse(fd_mouse, &x_anchor, &y_anchor, 159, 119);

    /* Aplica algoritmo de zoom in selecionado */
    printf("Aplicando algoritmo: ");
    switch (estado.algoritmo_in) {
        case ZOOM_IN_VIZINHO:
            printf("Vizinho mais proximo\n");
            vizinho_mais_proximo(x_anchor, y_anchor);
            break;
        case ZOOM_IN_REPLICACAO:
            printf("Replicacao de pixels\n");
            replicacao_pixel(x_anchor, y_anchor);
            break;
        default:
            controle_imagem(0);
            return 0;
    }

    estado.zoom_in_aplicado = 1;
    printf(">>> Zoom In GLOBAL aplicado com sucesso!\n");
    return 1;
}

/**
 * @brief Aplica zoom out globalmente (na imagem inteira)
 * 
 * Reduz a imagem ampliada de volta ao tamanho original.
 * Opera diretamente no coprocessador sem mapeamento adicional.
 */
void aplicar_zoom_out_global(void) {
    /* Validações de pré-condições */
    if (!estado.zoom_in_aplicado) {
        printf("Erro: Voce deve aplicar Zoom In primeiro!\n");
        return;
    }
    if (estado.algoritmo_out == ZOOM_OUT_NONE) {
        printf("Erro: Nenhum algoritmo de Zoom Out selecionado!\n");
        return;
    }

    printf("\n=== APLICANDO ZOOM OUT GLOBAL ===\n");

    /* Aplica algoritmo de zoom out selecionado */
    printf("Aplicando algoritmo: ");
    switch (estado.algoritmo_out) {
        case ZOOM_OUT_DECIMACAO:
            printf("Decimacao\n");
            decimacao();
            break;
        case ZOOM_OUT_MEDIA:
            printf("Media de blocos\n");
            media_de_blocos();
            break;
        default:
            controle_imagem(0);
            return;
    }

    estado.zoom_in_aplicado = 0;
    printf(">>> Zoom Out GLOBAL aplicado com sucesso!\n");
}

/**
 * @brief Modo interativo: permite mover a janela em tempo real
 * 
 * O usuário pode usar as setas do teclado para mover a janela
 * pelo frame e ver o resultado do zoom em diferentes regiões da imagem.
 * O zoom é reaplicado automaticamente a cada movimento.
 * 
 * Controles:
 *   - Setas: movem a janela (cima, baixo, esquerda, direita)
 *   - +/=: aumentam velocidade de movimento
 *   - -/_: diminuem velocidade de movimento
 *   - q/Q: sair do modo interativo
 */
void modo_janela_interativo(void) {
    int sair = 0;
    int pos_x, pos_y;
    int passo = 1;    /* Velocidade de movimento em pixels */

    /* Validações de pré-condições */
    if (!estado.janela.ativa) {
        printf("Erro: Selecione uma janela primeiro!\n");
        return;
    }

    if (!estado.zoom_in_aplicado) {
        printf("Erro: Aplique Zoom In primeiro para entrar no modo interativo!\n");
        return;
    }

    printf("\n=== MODO JANELA INTERATIVO (TECLAS) ===\n");
    printf("Setas: mover janela | +/- ajusta velocidade | q: sair\n");

    /* Posição inicial da janela */
    pos_x = estado.janela.x_inicial;
    pos_y = estado.janela.y_inicial;

    while (!sair) {
        int c = getchar();

        /* Detecta sequências de escape ANSI (setas do teclado) */
        if (c == 27) {    /* ESC */
            char s1 = getchar();
            if (s1 == '[') {
                char s2 = getchar();
                int nova_x = pos_x;
                int nova_y = pos_y;
                
                /* Processa direção baseada no código da seta */
                if (s2 == 'A') {          /* Seta para cima */
                    nova_y -= passo;
                } else if (s2 == 'B') {   /* Seta para baixo */
                    nova_y += passo;
                } else if (s2 == 'C') {   /* Seta para direita */
                    nova_x += passo;
                } else if (s2 == 'D') {   /* Seta para esquerda */
                    nova_x -= passo;
                }
                
                /* Limita coordenadas para manter janela dentro da tela */
                nova_x = clamp(nova_x, 0, SCREEN_WIDTH - estado.janela.largura);
                nova_y = clamp(nova_y, 0, SCREEN_HEIGHT - estado.janela.altura);

                /* Se houve movimento, atualiza janela e reaplica zoom */
                if (nova_x != pos_x || nova_y != pos_y) {
                    pos_x = nova_x;
                    pos_y = nova_y;

                    /* Atualiza coordenadas da janela no estado global */
                    estado.janela.x_inicial = pos_x;
                    estado.janela.y_inicial = pos_y;
                    estado.janela.x_final = pos_x + estado.janela.largura - 1;
                    estado.janela.y_final = pos_y + estado.janela.altura - 1;

                    /* Reaplica zoom na nova posição */
                    reaplicar_zoom_in_janela_interativo();

                    /* Atualiza feedback visual em tempo real */
                    printf("\r Janela: (%3d, %3d) ate (%3d, %3d)  passo=%d   ",
                           estado.janela.x_inicial, estado.janela.y_inicial,
                           estado.janela.x_final, estado.janela.y_final, passo);
                    fflush(stdout);
                }
            }
        } 
        /* Aumenta velocidade de movimento */
        else if (c == '+' || c == '=') {
            if (passo < 20) passo++;
            printf("\r Velocidade (passo) = %d   ", passo);
            fflush(stdout);
        } 
        /* Diminui velocidade de movimento */
        else if (c == '-' || c == '_') {
            if (passo > 1) passo--;
            printf("\r Velocidade (passo) = %d   ", passo);
            fflush(stdout);
        } 
        /* Sair do modo interativo */
        else if (c == 'q' || c == 'Q') {
            sair = 1;
            printf("\n>>> Saindo do modo janela.\n");
        }
    }
}

/*==============================================================================
 * NAVEGAÇÃO DE MENUS
 *============================================================================*/

/**
 * @brief Gerencia navegação em um menu usando mouse e teclado
 * 
 * Sistema de navegação híbrido que permite:
 * - Navegar opções com setas do teclado
 * - Confirmar com botão direito do mouse
 * - Atalhos globais (+/- para zoom) disponíveis em qualquer momento
 * 
 * @param fd_mouse      File descriptor do dispositivo de mouse
 * @param titulo        Título do menu a ser exibido
 * @param opcoes        Array de strings com as opções do menu
 * @param num_opcoes    Número total de opções no menu
 * @param opcao_atual   Índice da opção inicialmente selecionada
 * @return              Índice da opção confirmada pelo usuário
 */
int navegar_menu(int fd_mouse, const char *titulo, const char **opcoes, int num_opcoes, int opcao_atual) {
    struct input_event ev;
    fd_set fds;
    int confirmado = 0;

    /* Exibe menu inicial */
    exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);

    while (!confirmado) {
        /* Prepara conjunto de file descriptors para monitoramento */
        FD_ZERO(&fds);
        FD_SET(fd_mouse, &fds);   /* Monitora eventos do mouse */
        FD_SET(0, &fds);          /* Monitora eventos do teclado (stdin) */

        {
            int maxfd = fd_mouse > 0 ? fd_mouse : 0;

            /* Aguarda entrada de mouse ou teclado (bloqueante) */
            select(maxfd + 1, &fds, NULL, NULL, NULL);

            /* Processa eventos do mouse */
            if (FD_ISSET(fd_mouse, &fds)) {
                if (read(fd_mouse, &ev, sizeof(ev)) > 0) {
                    /* Botão direito confirma a opção selecionada */
                    if (ev.type == EV_KEY && ev.code == BTN_RIGHT && ev.value == 1) {
                        confirmado = 1;
                        printf("\n>>> Opcao confirmada: %s\n", opcoes[opcao_atual]);
                    }
                }
            }

            /* Processa eventos do teclado */
            if (FD_ISSET(0, &fds)) {
                char c = getchar();

                /* Detecta sequências de escape ANSI (setas) */
                if (c == 27) {
                    char seq1 = getchar();
                    if (seq1 == '[') {
                        char seq2 = getchar();
                        
                        /* Seta para cima: move para opção anterior */
                        if (seq2 == 'A') {
                            opcao_atual--;
                            if (opcao_atual < 0) opcao_atual = num_opcoes - 1;
                            exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);
                        } 
                        /* Seta para baixo: move para próxima opção */
                        else if (seq2 == 'B') {
                            opcao_atual++;
                            if (opcao_atual >= num_opcoes) opcao_atual = 0;
                            exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);
                        }
                    }
                } 
                /* Atalho global: aplicar zoom in */
                else if (c == '+' || c == '=') {
                    if (estado.janela.ativa) {
                        /* Modo janela: aplica zoom e entra em modo interativo */
                        if (aplicar_zoom_in_janela()) {
                            printf("\n>>> Entrando no modo interativo (teclas)...\n");
                            printf("Pressione qualquer tecla para continuar...\n");
                            getchar();
                            modo_janela_interativo();
                        } else {
                            printf("\nPressione qualquer tecla para continuar...\n");
                            getchar();
                        }
                    } else {
                        /* Modo global: aplica zoom diretamente */
                        aplicar_zoom_in_global(fd_mouse);
                        printf("\nPressione qualquer tecla para continuar...\n");
                        getchar();
                    }
                    /* Redesenha menu após operação */
                    exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);
                } 
                /* Atalho global: aplicar zoom out */
                else if (c == '-' || c == '_') {
                    if (estado.janela.ativa) {
                        aplicar_zoom_out_janela();
                    } else {
                        aplicar_zoom_out_global();
                    }
                    printf("\nPressione qualquer tecla para continuar...\n");
                    getchar();
                    /* Redesenha menu após operação */
                    exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);
                }
            }
        }
    }

    return opcao_atual;
}

/**
 * @brief Menu para seleção de algoritmo de Zoom In
 * 
 * Permite ao usuário escolher entre os algoritmos de ampliação disponíveis
 * ou desativar o zoom in.
 * 
 * @param fd_mouse  File descriptor do dispositivo de mouse
 */
void menu_zoom_in(int fd_mouse) {
    int opcao = navegar_menu(fd_mouse, "ALGORITMOS ZOOM IN", opcoes_zoom_in, NUM_OPCOES_ZOOM_IN, 0);

    switch (opcao) {
        case 0:    /* Vizinho mais próximo */
            estado.algoritmo_in = ZOOM_IN_VIZINHO;
            printf(">>> Algoritmo selecionado: Vizinho mais proximo\n");
            break;
        case 1:    /* Replicação de pixels */
            estado.algoritmo_in = ZOOM_IN_REPLICACAO;
            printf(">>> Algoritmo selecionado: Replicacao de pixels\n");
            break;
        case 2:    /* Desativar */
            estado.algoritmo_in = ZOOM_IN_NONE;
            printf(">>> Zoom In desativado\n");
            break;
        case 3:    /* Voltar */
            break;
    }
}

/**
 * @brief Menu para seleção de algoritmo de Zoom Out
 * 
 * Permite ao usuário escolher entre os algoritmos de redução disponíveis
 * ou desativar o zoom out.
 * 
 * @param fd_mouse  File descriptor do dispositivo de mouse
 */
void menu_zoom_out(int fd_mouse) {
    int opcao = navegar_menu(fd_mouse, "ALGORITMOS ZOOM OUT", opcoes_zoom_out, NUM_OPCOES_ZOOM_OUT, 0);

    switch (opcao) {
        case 0:    /* Decimação */
            estado.algoritmo_out = ZOOM_OUT_DECIMACAO;
            printf(">>> Algoritmo selecionado: Decimacao\n");
            break;
        case 1:    /* Média de blocos */
            estado.algoritmo_out = ZOOM_OUT_MEDIA;
            printf(">>> Algoritmo selecionado: Media de blocos\n");
            break;
        case 2:    /* Desativar */
            estado.algoritmo_out = ZOOM_OUT_NONE;
            printf(">>> Zoom Out desativado\n");
            break;
        case 3:    /* Voltar */
            break;
    }
}

/**
 * @brief Inicializa o estado do sistema com valores padrão
 * 
 * Reseta todos os parâmetros do sistema para valores iniciais seguros:
 * - Algoritmos desativados
 * - Janela desativada
 * - Buffers zerados
 */
void inicializar_estado(void) {
    estado.algoritmo_in = ZOOM_IN_NONE;
    estado.algoritmo_out = ZOOM_OUT_NONE;
    estado.janela.ativa = 0;
    estado.janela.x_inicial = 0;
    estado.janela.y_inicial = 0;
    estado.janela.x_final = 0;
    estado.janela.y_final = 0;
    estado.janela.largura = 0;
    estado.janela.altura = 0;
    estado.zoom_in_aplicado = 0;
    memset(estado.vetor_original, 0, sizeof(estado.vetor_original));
    memset(estado.vetor_processado, 0, sizeof(estado.vetor_processado));
}

/*==============================================================================
 * FUNÇÃO PRINCIPAL
 *============================================================================*/

/**
 * @brief Ponto de entrada do programa
 * 
 * Sequência de inicialização:
 * 1. Abre dispositivo de mouse
 * 2. Inicializa estado do sistema
 * 3. Mapeia endereços da FPGA
 * 4. Configura terminal para modo não-canônico
 * 5. Executa loop principal do menu interativo
 * 6. Realiza limpeza de recursos ao sair
 * 
 * @return 0 em caso de sucesso, 1 em caso de erro na inicialização
 */
int main(void) {
    const char *mouse_dev = "/dev/input/event0";
    int fd_mouse;
    int opcao_atual = 0;

    /* Abre dispositivo de mouse */
    fd_mouse = open(mouse_dev, O_RDONLY);
    if (fd_mouse < 0) {
        perror("Erro ao abrir mouse");
        return 1;
    }

    /* Inicializa sistema */
    printf("Inicializando sistema...\n");
    inicializar_estado();

    /* Mapeia endereços da FPGA para acesso aos registradores */
    printf("Mapeando enderecos...\n");
    mapear_enderecos();
    printf("Enderecos mapeados com sucesso.\n");

    /* Configura terminal para modo não-canônico (leitura imediata) */
    init_keyboard();

    printf("\n>>> Sistema pronto! Use as setas e botao direito do mouse.\n");
    printf(">>> Use [+] para Zoom In e [-] para Zoom Out a qualquer momento.\n\n");

    /* Loop principal do menu */
    while (1) {
        const char **menu_atual = obter_menu_principal();
        opcao_atual = navegar_menu(fd_mouse, "MENU PRINCIPAL",
                                   menu_atual, NUM_OPCOES_PRINCIPAL, opcao_atual);

        switch (opcao_atual) {
            /* Opção 0: Selecionar algoritmo Zoom In */
            case 0:
                menu_zoom_in(fd_mouse);
                break;

            /* Opção 1: Selecionar algoritmo Zoom Out */
            case 1:
                menu_zoom_out(fd_mouse);
                break;

            /* Opção 2: Selecionar/Desativar janela */
            case 2:
                if (estado.janela.ativa) {
                    /* Janela já está ativa: desativar */
                    desativar_janela();
                } else {
                    /* Nenhuma janela ativa: selecionar nova */
                    if (selecionar_janela(fd_mouse)) {
                        /* Carrega imagem original para buffer */
                        carregar_imagem_original();
                        printf("\n>>> Janela configurada! Use [+] para aplicar Zoom In.\n");
                    }
                }
                break;

            /* Opção 3: Enviar imagem para FPGA */
            case 3:
                printf("\n=== ENVIANDO IMAGEM PARA FPGA ===\n");
                printf("Carregando e enviando imagem...\n");
                enviar_imagem_fpga("talarelo.pgm");
                carregar_imagem_original();
                printf(">>> Imagem enviada com sucesso!\n");
                break;

            /* Opção 4: Ler pixel específico */
            case 4:
            {
                int x_read, y_read;
                int endereco;
                int pixel;

                printf("\n=== LER PIXEL ESPECIFICO ===\n");
                /* Usuário seleciona coordenada com mouse */
                selecionar_coordenada_mouse(fd_mouse, &x_read, &y_read,
                                            SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1);
                
                /* Calcula endereço linear do pixel */
                endereco = y_read * SCREEN_WIDTH + x_read;
                
                printf("Lendo pixel...\n");
                /* Lê pixel da memória de exibição (1) da FPGA */
                pixel = carregar_pixel(endereco, 1);
                
                printf("\n>>> Pixel em (%d, %d): 0x%02X (decimal: %d)\n",
                       x_read, y_read, pixel, pixel);
                break;
            }

            /* Opção 5: Sair */
            case 5:
                printf("\nSaindo do programa...\n");
                goto cleanup;
        }

        /* Pausa antes de retornar ao menu */
        printf("\nPressione qualquer tecla para voltar ao menu...\n");
        getchar();
    }

cleanup:
    /* Limpeza de recursos */
    restore_keyboard();         /* Restaura terminal para modo normal */
    close(fd_mouse);            /* Fecha dispositivo de mouse */
    fechar_enderecos();         /* Desmapeia memória e fecha /dev/mem */
    return 0;
}
