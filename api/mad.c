#include "api.h"
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/input.h>
#include <sys/select.h>
#include <termios.h>

/* ---------- DESATIVA O BUFFER DO TERMINAL (modo raw) ---------- */
static struct termios old, new_term;

void init_keyboard() {
    tcgetattr(0, &old);
    new_term = old;
    new_term.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(0, TCSANOW, &new_term);
}

void restore_keyboard() {
    tcsetattr(0, TCSANOW, &old);
}

/* Opções do menu */
const char *opcoes_menu[] = {
    "1 - Vizinho mais proximo (ZOOM IN)",
    "2 - Replicacao de pixels (ZOOM IN)",
    "3 - Decimacao (ZOOM OUT)",
    "4 - Media de pixels (ZOOM OUT)",
    "5 - Enviar imagem para FPGA",
    "6 - Enviar intervalo de pixels",
    "7 - Ler pixel especifico",
    "q - Sair"
};
const int NUM_OPCOES = 8;

/* Exibe o menu com a opção selecionada destacada */
void exibir_menu(int opcao_selecionada) {
    printf("\n\n==================================\n");
    printf("       MENU DE OPERACOES\n");
    printf("==================================\n");
    printf(" SETAS: Navegar | BOTAO DIREITO: Confirmar\n");
    printf("==================================\n\n");

    int i;
    for (i = 0; i < NUM_OPCOES; i++) {
        if (i == opcao_selecionada) {
            printf("  >>> [ %s ] <<<\n", opcoes_menu[i]);
        } else {
            printf("      %s\n", opcoes_menu[i]);
        }
    }
    printf("\n==================================\n");
    fflush(stdout);
}

/* Função para esperar seleção de coordenada com o mouse (botão direito confirma) */
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

                if (x < 0) x = 0;
                if (x > x_max) x = x_max;
                if (y < 0) y = 0;
                if (y > y_max) y = y_max;

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

/* Navega no menu com setas e confirma com botão direito do mouse */
int navegar_menu(int fd_mouse, int opcao_atual) {
    struct input_event ev;
    fd_set fds;
    int confirmado = 0;

    exibir_menu(opcao_atual);

    while (!confirmado) {
        FD_ZERO(&fds);
        FD_SET(fd_mouse, &fds);
        FD_SET(0, &fds);

        int maxfd = fd_mouse > 0 ? fd_mouse : 0;

        select(maxfd + 1, &fds, NULL, NULL, NULL);

        /* Mouse - botão direito confirma */
        if (FD_ISSET(fd_mouse, &fds)) {
            if (read(fd_mouse, &ev, sizeof(ev)) > 0) {
                if (ev.type == EV_KEY && ev.code == BTN_RIGHT && ev.value == 1) {
                    confirmado = 1;
                    printf("\n>>> Opcao confirmada: %s\n", opcoes_menu[opcao_atual]);
                }
            }
        }

        /* Teclado - setas navegam */
        if (FD_ISSET(0, &fds)) {
            char c = getchar();

            if (c == 27) {  // ESC (início de sequência de seta)
                char seq1 = getchar();
                if (seq1 == '[') {
                    char seq2 = getchar();
                    if (seq2 == 'A') {  // Seta CIMA
                        opcao_atual--;
                        if (opcao_atual < 0) opcao_atual = NUM_OPCOES - 1;
                        exibir_menu(opcao_atual);
                    } else if (seq2 == 'B') {  // Seta BAIXO
                        opcao_atual++;
                        if (opcao_atual >= NUM_OPCOES) opcao_atual = 0;
                        exibir_menu(opcao_atual);
                    }
                }
            }
        }
    }

    return opcao_atual;
}

int main() {
    const char *mouse_dev = "/dev/input/event0";

    int fd_mouse = open(mouse_dev, O_RDONLY);
    if (fd_mouse < 0) {
        perror("Erro ao abrir mouse");
        return 1;
    }

    // Mapeia endereços da FPGA
    printf("Mapeando enderecos...\n");
    mapear_enderecos();
    printf("Enderecos mapeados com sucesso.\n");

    init_keyboard();

    int opcao_atual = 0;

    printf("\n>>> Sistema pronto! Use as setas e botao direito do mouse.\n");

    while (1) {
        // Navega no menu e aguarda confirmação
        opcao_atual = navegar_menu(fd_mouse, opcao_atual);

        if (opcao_atual == 0) {
            // Vizinho mais próximo
            printf("\n=== VIZINHO MAIS PROXIMO ===\n");
            int x_base, y_base;
            selecionar_coordenada_mouse(fd_mouse, &x_base, &y_base, 159, 119);
            
            printf("Executando operacao...\n");
            vizinho_mais_proximo(x_base, y_base);
            printf(">>> Operacao concluida! Resultado exibido no monitor VGA.\n");
        }
        else if (opcao_atual == 1) {
            // Replicação de pixels
            printf("\n=== REPLICACAO DE PIXELS ===\n");
            int x_base, y_base;
            selecionar_coordenada_mouse(fd_mouse, &x_base, &y_base, 159, 119);
            
            printf("Executando operacao...\n");
            replicacao_pixel(x_base, y_base);
            printf(">>> Operacao concluida! Resultado exibido no monitor VGA.\n");
        }
        else if (opcao_atual == 2) {
            // Decimação
            printf("\n=== DECIMACAO ===\n");
            printf("Executando operacao...\n");
            decimacao();
            printf(">>> Operacao concluida! Resultado exibido no monitor VGA.\n");
        }
        else if (opcao_atual == 3) {
            // Média de blocos
            printf("\n=== MEDIA DE BLOCOS ===\n");
            printf("Executando operacao...\n");
            media_de_blocos();
            printf(">>> Operacao concluida! Resultado exibido no monitor VGA.\n");
        }
        else if (opcao_atual == 4) {
            // Enviar imagem para FPGA
            printf("\n=== ENVIANDO IMAGEM PARA FPGA ===\n");
            printf("Carregando e enviando imagem...\n");
            enviar_imagem_fpga("imagem.pgm");
            printf(">>> Imagem enviada com sucesso! Exibida no monitor VGA.\n");
        }
        else if (opcao_atual == 5) {
            // Enviar intervalo de pixels
            printf("\n=== ENVIAR INTERVALO DE PIXELS ===\n");
            int x0, y0, xf, yf;

            printf("\n-- Selecione o ponto INICIAL --\n");
            selecionar_coordenada_mouse(fd_mouse, &x0, &y0, 319, 239);

            printf("\n-- Selecione o ponto FINAL --\n");
            selecionar_coordenada_mouse(fd_mouse, &xf, &yf, 319, 239);

            // Garantir ordem correta
            if (x0 > xf) { int t = x0; x0 = xf; xf = t; }
            if (y0 > yf) { int t = y0; y0 = yf; yf = t; }

            printf("\nEnviando pixels de (%d,%d) a (%d,%d)...\n", x0, y0, xf, yf);
            int px, py;
            
            for (py = y0; py <= yf; py++) {
                for (px = x0; px <= xf; px++) {
                    int endereco = py * 320 + px;
                    enviar_pixel(0, endereco);
                }
            }
            printf(">>> Intervalo enviado com sucesso!\n");
        }
        else if (opcao_atual == 6) {
            // Ler pixel específico
            printf("\n=== LER PIXEL ESPECIFICO ===\n");
            int x_read, y_read;
            selecionar_coordenada_mouse(fd_mouse, &x_read, &y_read, 319, 239);

            int endereco = y_read * 320 + x_read;
            printf("Lendo pixel...\n");
            int pixel = carregar_pixel(endereco, 1);
            printf("\n>>> Pixel em (%d, %d): 0x%02X (decimal: %d)\n", x_read, y_read, pixel, pixel);
        }
        else if (opcao_atual == 7) {
            // Sair
            printf("\nSaindo do programa...\n");
            break;
        }

        printf("\nPressione qualquer tecla para voltar ao menu...\n");
        getchar();
    }

    restore_keyboard();
    close(fd_mouse);
    fechar_enderecos();
    return 0;
}
