#include "api.h"
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/input.h>
#include <sys/select.h>
#include <termios.h>
#include <string.h>

/* ==================== CONSTANTES ==================== */
#define SCREEN_WIDTH  320
#define SCREEN_HEIGHT 240
#define TOTAL_PIXELS  76800
#define MAX_WINDOW_SIZE 100

/* ==================== ESTRUTURAS ==================== */
typedef enum {
    ZOOM_IN_VIZINHO = 0,
    ZOOM_IN_REPLICACAO,
    ZOOM_IN_NONE
} AlgoritmoZoomIn;

typedef enum {
    ZOOM_OUT_DECIMACAO = 0,
    ZOOM_OUT_MEDIA,
    ZOOM_OUT_NONE
} AlgoritmoZoomOut;

typedef struct {
    int x_inicial;
    int y_inicial;
    int x_final;
    int y_final;
    int largura;
    int altura;
    int ativa;
} Janela;

typedef struct {
    AlgoritmoZoomIn algoritmo_in;
    AlgoritmoZoomOut algoritmo_out;
    Janela janela;
    int zoom_in_aplicado; /* vale para global ou janela */
    int vetor_original[TOTAL_PIXELS];
    int vetor_processado[TOTAL_PIXELS];
} EstadoSistema;

/* ==================== VARIAVEIS GLOBAIS ==================== */
static struct termios old_term, new_term;
static EstadoSistema estado;

/* ==================== TERMINAL ==================== */
void init_keyboard(void) {
    tcgetattr(0, &old_term);
    new_term = old_term;
    new_term.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(0, TCSANOW, &new_term);
}

void restore_keyboard(void) {
    tcsetattr(0, TCSANOW, &old_term);
}

/* ==================== UTILIDADES ==================== */
int clamp(int valor, int min, int max) {
    if (valor < min) return min;
    if (valor > max) return max;
    return valor;
}

void limpar_tela(void) {
    printf("\033[2J\033[H");
    fflush(stdout);
}

/* ==================== EXIBICAO DE MENUS ==================== */

/* Menu dinâmico - muda baseado no estado da janela */
const char *opcoes_menu_sem_janela[] = {
    "1 - Selecionar algoritmo ZOOM IN",
    "2 - Selecionar algoritmo ZOOM OUT",
    "3 - Selecionar janela",
    "4 - Enviar imagem para FPGA",
    "5 - Ler pixel especifico",
    "q - Sair"
};

const char *opcoes_menu_com_janela[] = {
    "1 - Selecionar algoritmo ZOOM IN",
    "2 - Selecionar algoritmo ZOOM OUT",
    "3 - Desativar janela",
    "4 - Enviar imagem para FPGA",
    "5 - Ler pixel especifico",
    "q - Sair"
};

const int NUM_OPCOES_PRINCIPAL = 6;

const char *opcoes_zoom_in[] = {
    "1 - Vizinho mais proximo",
    "2 - Replicacao de pixels",
    "3 - Nenhum (desativar)",
    "Voltar"
};
const int NUM_OPCOES_ZOOM_IN = 4;

const char *opcoes_zoom_out[] = {
    "1 - Decimacao",
    "2 - Media de blocos",
    "3 - Nenhum (desativar)",
    "Voltar"
};
const int NUM_OPCOES_ZOOM_OUT = 4;

const char** obter_menu_principal(void) {
    if (estado.janela.ativa) {
        return opcoes_menu_com_janela;
    }
    return opcoes_menu_sem_janela;
}

void exibir_status(void) {
    printf("==================================\n");
    printf("         STATUS ATUAL\n");
    printf("==================================\n");

    printf(" Zoom In: ");
    switch (estado.algoritmo_in) {
        case ZOOM_IN_VIZINHO:     printf("Vizinho mais proximo\n"); break;
        case ZOOM_IN_REPLICACAO:  printf("Replicacao de pixels\n"); break;
        case ZOOM_IN_NONE:        printf("Nenhum\n"); break;
    }

    printf(" Zoom Out: ");
    switch (estado.algoritmo_out) {
        case ZOOM_OUT_DECIMACAO:  printf("Decimacao\n"); break;
        case ZOOM_OUT_MEDIA:      printf("Media de blocos\n"); break;
        case ZOOM_OUT_NONE:       printf("Nenhum\n"); break;
    }

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

void exibir_menu_generico(const char *titulo, const char **opcoes, int num_opcoes, int selecionada) {
    int i;
    limpar_tela();
    exibir_status();

    printf("\n==================================\n");
    printf("       %s\n", titulo);
    printf("==================================\n");
    printf(" SETAS: Navegar | BOTAO DIREITO: Confirmar\n");
    printf("==================================\n\n");

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

/* ==================== ENTRADA DO MOUSE ==================== */
void selecionar_coordenada_mouse(int fd_mouse, int *out_x, int *out_y, int x_max, int y_max) {
    struct input_event ev;
    int x = x_max / 2, y = y_max / 2;
    int confirmado = 0;

    printf("\n>>> Mova o mouse para selecionar a coordenada.\n");
    printf(">>> Pressione BOTAO DIREITO para confirmar.\n\n");

    while (!confirmado) {
        if (read(fd_mouse, &ev, sizeof(ev)) > 0) {
            if (ev.type == EV_REL) {
                if (ev.code == REL_X) x += ev.value;
                if (ev.code == REL_Y) y += ev.value;

                x = clamp(x, 0, x_max);
                y = clamp(y, 0, y_max);

                printf("\r    Coordenada: X = %3d  |  Y = %3d      ", x, y);
                fflush(stdout);
            }

            if (ev.type == EV_KEY && ev.code == BTN_RIGHT && ev.value == 1) {
                confirmado = 1;
                printf("\n\n>>> CONFIRMADO: X = %d, Y = %d\n", x, y);
            }
        }
    }

    *out_x = x;
    *out_y = y;
}

/* ==================== GERENCIAMENTO DE JANELA ==================== */
int selecionar_janela(int fd_mouse) {
    int x0, y0, xf, yf;
    int largura, altura;

    printf("\n=== SELECAO DE JANELA ===\n");
    printf("A janela deve ter no maximo %dx%d pixels.\n\n", MAX_WINDOW_SIZE, MAX_WINDOW_SIZE);

    printf("-- Selecione o ponto INICIAL --\n");
    selecionar_coordenada_mouse(fd_mouse, &x0, &y0, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1);

    printf("\n-- Selecione o ponto FINAL --\n");
    selecionar_coordenada_mouse(fd_mouse, &xf, &yf, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1);

    if (x0 > xf) { int t = x0; x0 = xf; xf = t; }
    if (y0 > yf) { int t = y0; y0 = yf; yf = t; }

    largura = xf - x0 + 1;
    altura = yf - y0 + 1;

    if (largura > MAX_WINDOW_SIZE || altura > MAX_WINDOW_SIZE) {
        printf("\nErro: A janela deve ser no maximo %dx%d!\n", MAX_WINDOW_SIZE, MAX_WINDOW_SIZE);
        printf("Sua janela: %dx%d\n", largura, altura);
        return 0;
    }

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

/* ==================== OPERACOES DE ZOOM (AJUDANTES) ==================== */
void carregar_imagem_original(void) {
    int i;
    printf("Carregando imagem original da memoria...\n");
    for (i = 0; i < TOTAL_PIXELS; i++) {
        estado.vetor_original[i] = carregar_pixel(i, 0);
    }
    printf("Imagem carregada.\n");
}

/* Redesenha aplicando resultado de zoom-in (janela) sobre a imagem original */
void render_zoom_in_result(void) {
    int i;
    int x, y, rel_x, rel_y, fonte_x, fonte_y, endereco_fonte;
    int offset_x, offset_y;

    offset_x = estado.janela.largura / 2;
    offset_y = estado.janela.altura / 2;

    for (i = 0; i < TOTAL_PIXELS; i++) {
        x = i % SCREEN_WIDTH;
        y = i / SCREEN_WIDTH;

        if (x >= estado.janela.x_inicial && x <= estado.janela.x_final &&
            y >= estado.janela.y_inicial && y <= estado.janela.y_final) {

            rel_x = x - estado.janela.x_inicial;
            rel_y = y - estado.janela.y_inicial;
            fonte_x = offset_x + rel_x;
            fonte_y = offset_y + rel_y;
            endereco_fonte = fonte_y * SCREEN_WIDTH + fonte_x;

            if (endereco_fonte < TOTAL_PIXELS && estado.vetor_processado[endereco_fonte] != 0x000000) {
                enviar_pixel(estado.vetor_processado[endereco_fonte], i);
            } else {
                enviar_pixel(estado.vetor_original[i], i);
            }
        } else {
            enviar_pixel(estado.vetor_original[i], i);
        }
    }
}

/* Reaplica todo o pipeline de zoom-in para a posição atual da janela (para modo interativo) */
void reaplicar_zoom_in_janela_interativo(void) {
    int i;
    int x, y;
    int vetor_auxiliar[TOTAL_PIXELS];

    /* mascara e envio */
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
    for (i = 0; i < TOTAL_PIXELS; i++) {
        enviar_pixel(vetor_auxiliar[i], i);
    }

    usleep(100000);

    /* algoritmo de zoom in */
    switch (estado.algoritmo_in) {
        case ZOOM_IN_VIZINHO:
            vizinho_mais_proximo(estado.janela.x_inicial, estado.janela.y_inicial);
            break;
        case ZOOM_IN_REPLICACAO:
            replicacao_pixel(estado.janela.x_inicial, estado.janela.y_inicial);
            break;
        default:
            return;
    }

    usleep(100000);

    /* carrega processado e redesenha */
    for (i = 0; i < TOTAL_PIXELS; i++) {
        estado.vetor_processado[i] = carregar_pixel(i, 1);
    }
    render_zoom_in_result();
}

/* Zoom In na janela */
int aplicar_zoom_in_janela(void) {
    int i;
    int x, y;
    int vetor_auxiliar[TOTAL_PIXELS];

    if (!estado.janela.ativa) {
        printf("Erro: Nenhuma janela selecionada!\n");
        return 0;
    }

    if (estado.algoritmo_in == ZOOM_IN_NONE) {
        printf("Erro: Nenhum algoritmo de Zoom In selecionado!\n");
        return 0;
    }

    if (estado.zoom_in_aplicado) {
        printf("Erro: Zoom In ja foi aplicado!  Use Zoom Out primeiro.\n");
        return 0;
    }

    printf("\n=== APLICANDO ZOOM IN NA JANELA ===\n");

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

    for (i = 0; i < TOTAL_PIXELS; i++) {
        enviar_pixel(vetor_auxiliar[i], i);
    }

    usleep(100000);

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
            return 0;
    }

    usleep(100000);

    for (i = 0; i < TOTAL_PIXELS; i++) {
        estado.vetor_processado[i] = carregar_pixel(i, 1);
    }

    render_zoom_in_result();

    estado.zoom_in_aplicado = 1;
    printf(">>> Zoom In aplicado com sucesso!\n");
    return 1;
}

/* Zoom Out na janela */
void aplicar_zoom_out_janela(void) {
    int i;
    int x, y, rel_x, rel_y, fonte_x, fonte_y, endereco_fonte;
    int min_x, max_x, min_y, max_y;
    int vetor_resultado[TOTAL_PIXELS];

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

    for (i = 0; i < TOTAL_PIXELS; i++) {
        enviar_pixel(estado.vetor_processado[i], i);
    }

    usleep(100000);

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
            return;
    }

    usleep(100000);

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

        if (x >= estado.janela.x_inicial && x <= estado.janela.x_final - 1 &&
            y >= estado.janela.y_inicial && y <= estado.janela.y_final) {

            rel_x = x - estado.janela.x_inicial;
            rel_y = y - estado.janela.y_inicial;
            fonte_x = min_x + 1 + rel_x;
            fonte_y = min_y + rel_y;
            endereco_fonte = fonte_y * SCREEN_WIDTH + fonte_x;

            if (endereco_fonte < TOTAL_PIXELS && vetor_resultado[endereco_fonte] != 0x000000) {
                enviar_pixel(vetor_resultado[endereco_fonte], i);
            } else {
                enviar_pixel(estado.vetor_original[i], i);
            }
        } else {
            enviar_pixel(estado.vetor_original[i], i);
        }
    }

    estado.zoom_in_aplicado = 0;
    printf(">>> Zoom Out aplicado com sucesso!\n");
}

/* Zoom In global (sem janela) - pede coordenadas limitadas a 0..159 / 0..119 */
int aplicar_zoom_in_global(int fd_mouse) {
    int i;
    int x_anchor = 0, y_anchor = 0;

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
    selecionar_coordenada_mouse(fd_mouse, &x_anchor, &y_anchor, 159, 119);

    for (i = 0; i < TOTAL_PIXELS; i++) {
        enviar_pixel(estado.vetor_original[i], i);
    }

    usleep(100000);

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
            return 0;
    }

    usleep(100000);

    for (i = 0; i < TOTAL_PIXELS; i++) {
        estado.vetor_processado[i] = carregar_pixel(i, 1);
        enviar_pixel(estado.vetor_processado[i], i);
    }

    estado.zoom_in_aplicado = 1;
    printf(">>> Zoom In GLOBAL aplicado com sucesso!\n");
    return 1;
}

/* Zoom Out global (sem janela) */
void aplicar_zoom_out_global(void) {
    int i;
    int vetor_resultado[TOTAL_PIXELS];

    if (!estado.zoom_in_aplicado) {
        printf("Erro: Voce deve aplicar Zoom In primeiro!\n");
        return;
    }
    if (estado.algoritmo_out == ZOOM_OUT_NONE) {
        printf("Erro: Nenhum algoritmo de Zoom Out selecionado!\n");
        return;
    }

    printf("\n=== APLICANDO ZOOM OUT GLOBAL ===\n");

    for (i = 0; i < TOTAL_PIXELS; i++) {
        enviar_pixel(estado.vetor_processado[i], i);
    }

    usleep(100000);

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
            return;
    }

    usleep(100000);

    for (i = 0; i < TOTAL_PIXELS; i++) {
        vetor_resultado[i] = carregar_pixel(i, 1);
        enviar_pixel(vetor_resultado[i], i);
    }

    estado.zoom_in_aplicado = 0;
    printf(">>> Zoom Out GLOBAL aplicado com sucesso!\n");
}

/* ==================== MODO JANELA INTERATIVO (AGORA COM TECLADO) ==================== */
void modo_janela_interativo(void) {
    int sair = 0;
    int pos_x, pos_y;
    int passo = 1; /* velocidade inicial */

    if (!estado.janela.ativa) {
        printf("Erro: Selecione uma janela primeiro!\n");
        return;
    }

    if (!estado.zoom_in_aplicado) {
        printf("Erro: Aplique Zoom In primeiro para entrar no modo interativo!\n");
        return;
    }

    printf("\n=== MODO JANELA INTERATIVO (TECLAS) ===\n");
    printf("Setas: mover janela | +/- ajusta velocidade | q: sair | - (menos) fora do interativo faz Zoom Out\n");

    pos_x = estado.janela.x_inicial;
    pos_y = estado.janela.y_inicial;

    while (!sair) {
        int c = getchar();

        if (c == 27) { /* sequencia de seta: ESC [ A/B/C/D */
            char s1 = getchar();
            if (s1 == '[') {
                char s2 = getchar();
                int nova_x = pos_x;
                int nova_y = pos_y;
                if (s2 == 'A') { /* cima */
                    nova_y -= passo;
                } else if (s2 == 'B') { /* baixo */
                    nova_y += passo;
                } else if (s2 == 'C') { /* direita */
                    nova_x += passo;
                } else if (s2 == 'D') { /* esquerda */
                    nova_x -= passo;
                }
                nova_x = clamp(nova_x, 0, SCREEN_WIDTH - estado.janela.largura);
                nova_y = clamp(nova_y, 0, SCREEN_HEIGHT - estado.janela.altura);

                if (nova_x != pos_x || nova_y != pos_y) {
                    pos_x = nova_x;
                    pos_y = nova_y;

                    estado.janela.x_inicial = pos_x;
                    estado.janela.y_inicial = pos_y;
                    estado.janela.x_final = pos_x + estado.janela.largura - 1;
                    estado.janela.y_final = pos_y + estado.janela.altura - 1;

                    reaplicar_zoom_in_janela_interativo();

                    printf("\r Janela: (%3d, %3d) ate (%3d, %3d)  passo=%d   ",
                           estado.janela.x_inicial, estado.janela.y_inicial,
                           estado.janela.x_final, estado.janela.y_final, passo);
                    fflush(stdout);
                }
            }
        } else if (c == '+' || c == '=') {
            if (passo < 20) passo++;
            printf("\r Velocidade (passo) = %d   ", passo);
            fflush(stdout);
        } else if (c == '-' || c == '_') {
            if (passo > 1) passo--;
            printf("\r Velocidade (passo) = %d   ", passo);
            fflush(stdout);
        } else if (c == 'q' || c == 'Q') {
            sair = 1;
            printf("\n>>> Saindo do modo janela.\n");
        }
    }
}

/* ==================== NAVEGACAO DE MENU ==================== */
int navegar_menu(int fd_mouse, const char *titulo, const char **opcoes, int num_opcoes, int opcao_atual) {
    struct input_event ev;
    fd_set fds;
    int confirmado = 0;

    exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);

    while (!confirmado) {
        FD_ZERO(&fds);
        FD_SET(fd_mouse, &fds);
        FD_SET(0, &fds);

        {
            int maxfd = fd_mouse > 0 ? fd_mouse : 0;

            select(maxfd + 1, &fds, NULL, NULL, NULL);

            if (FD_ISSET(fd_mouse, &fds)) {
                if (read(fd_mouse, &ev, sizeof(ev)) > 0) {
                    if (ev.type == EV_KEY && ev.code == BTN_RIGHT && ev.value == 1) {
                        confirmado = 1;
                        printf("\n>>> Opcao confirmada: %s\n", opcoes[opcao_atual]);
                    }
                }
            }

            if (FD_ISSET(0, &fds)) {
                char c = getchar();

                if (c == 27) {
                    char seq1 = getchar();
                    if (seq1 == '[') {
                        char seq2 = getchar();
                        if (seq2 == 'A') {
                            opcao_atual--;
                            if (opcao_atual < 0) opcao_atual = num_opcoes - 1;
                            exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);
                        } else if (seq2 == 'B') {
                            opcao_atual++;
                            if (opcao_atual >= num_opcoes) opcao_atual = 0;
                            exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);
                        }
                    }
                } else if (c == '+' || c == '=') {
                    if (estado.janela.ativa) {
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
                        aplicar_zoom_in_global(fd_mouse);
                        printf("\nPressione qualquer tecla para continuar...\n");
                        getchar();
                    }
                    exibir_menu_generico(titulo, opcoes, num_opcoes, opcao_atual);
                } else if (c == '-' || c == '_') {
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

/* ==================== SUBMENUS ==================== */
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
            break;
    }
}

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
            break;
    }
}

/* ==================== INICIALIZACAO ==================== */
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

/* ==================== MAIN ==================== */
int main(void) {
    const char *mouse_dev = "/dev/input/event0";
    int fd_mouse;
    int opcao_atual = 0;

    fd_mouse = open(mouse_dev, O_RDONLY);
    if (fd_mouse < 0) {
        perror("Erro ao abrir mouse");
        return 1;
    }

    printf("Inicializando sistema...\n");
    inicializar_estado();

    printf("Mapeando enderecos...\n");
    mapear_enderecos();
    printf("Enderecos mapeados com sucesso.\n");

    init_keyboard();

    printf("\n>>> Sistema pronto!  Use as setas e botao direito do mouse.\n");
    printf(">>> Use [+] para Zoom In e [-] para Zoom Out a qualquer momento.\n\n");

    while (1) {
        const char **menu_atual = obter_menu_principal();
        opcao_atual = navegar_menu(fd_mouse, "MENU PRINCIPAL",
                                   menu_atual, NUM_OPCOES_PRINCIPAL, opcao_atual);

        switch (opcao_atual) {
            case 0:  /* Selecionar algoritmo Zoom In */
                menu_zoom_in(fd_mouse);
                break;

            case 1:  /* Selecionar algoritmo Zoom Out */
                menu_zoom_out(fd_mouse);
                break;

            case 2:  /* Selecionar janela OU Desativar janela */
                if (estado.janela.ativa) {
                    desativar_janela();
                } else {
                    if (selecionar_janela(fd_mouse)) {
                        carregar_imagem_original();
                        printf("\n>>> Janela configurada!  Use [+] para aplicar Zoom In.\n");
                    }
                }
                break;

            case 3:  /* Enviar imagem para FPGA */
                printf("\n=== ENVIANDO IMAGEM PARA FPGA ===\n");
                printf("Carregando e enviando imagem...\n");
                enviar_imagem_fpga("imagem.pgm");
                carregar_imagem_original();
                printf(">>> Imagem enviada com sucesso!\n");
                break;

            case 4:  /* Ler pixel específico */
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

            case 5:  /* Sair */
                printf("\nSaindo do programa...\n");
                goto cleanup;
        }

        printf("\nPressione qualquer tecla para voltar ao menu...\n");
        getchar();
    }

cleanup:
    restore_keyboard();
    close(fd_mouse);
    fechar_enderecos();
    return 0;
}
