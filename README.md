# Zoom Digital: Redimensionamento de Imagens com FPGA em Verilog

## Descrição do Projeto

Este repositório contém o projeto de um coprocessador gráfico dedicado ao **Redimensionamento de Imagens** (Zoom Digital e Downscale) implementado em **Verilog** para a **FPGA Cyclone V SE** da placa de desenvolvimento **DE1-SoC**. O sistema opera como um processador gráfico autossuficiente (co-processador), realizando todo o processamento de imagens diretamente na **Fabric Lógica (FPGA)**. O controle do zoom é feito através de chaves e botões a bordo, e a imagem final é exibida em tempo real via saída **VGA**.

O objetivo é simular um comportamento básico de interpolação visual, com foco na eficiência de hardware para processamento em tempo real.

### Requisitos Funcionais Implementados

O sistema foi desenvolvido para atender aos seguintes algoritmos de redimensionamento em passos de **2X**:

* **Ampliação (Zoom in - 2X):**
    * **Vizinho Mais Próximo (Nearest Neighbor Interpolation)**.
    * **Replicação de Pixel (Pixel Replication / Block Replication)**.
* **Redução (Zoom out - 2X):**
    * **Decimação / Amostragem (Nearest Neighbor for Zoom Out)**.
    * **Média de Blocos (Block Averaging / Downsampling with Averaging)**.

As imagens são tratadas em **escala de cinza**, onde cada pixel é representado por um número inteiro de **8 bits**. O projeto também prevê compatibilidade com o **Hard Processor System (HPS) ARM** da DE1-SoC, visando futuras etapas de desenvolvimento.

## Recursos Utilizados

![Image](https://github.com/user-attachments/assets/cd06616a-a5f0-446b-a090-6bb92ac9e4be)

### Hardware

| Componente | Detalhe | Finalidade no Projeto |
| :--- | :--- | :--- |
| **Placa de Desenvolvimento** | **DE1-SoC** | Plataforma principal de implementação. |
| **FPGA** | **Altera Cyclone V SE 5CSEMA5F31C6N** | Fabric Lógica para o co-processador gráfico. |
| **Memória** | **M10k block** | Armazenamento do *framebuffer* para a imagem original e a imagem processada (escala de cinza 8-bit). |
| **Saída de Vídeo** | **VGA DAC (ADV7123)** | Conversor Digital-Analógico de 8 bits para a saída VGA (15-pin D-SUB). Permite exibição em modos de alta resolução como SXGA ($1280 \times 1024$) a 100MHz. |
| **Controles de Usuário** | **Chaves Deslizantes (SW[9:0])** | Seleção do algoritmo de redimensionamento. **SW[9:0]** estão conectados ao FPGA e fornecem nível lógico alto (UP) ou baixo (DOWN). |
| **Controles de Usuário** | **Botões de Pressão (KEY[3:0])** | Ações de controle (ex: Reset e Redimensionamento de Imagem (Zoom-in e Zoom-out)). **KEY[3:0]** estão conectados ao FPGA e são **debounced** por *Schmitt Triggers*, sendo ideais para uso como clock ou reset. |

### Software

| Software | Versão | Uso |
| :--- | :--- | :--- |
| **Linguagem de Descrição de Hardware** | **Verilog** | Código fonte de todos os módulos lógicos. |
| **Ambiente de Desenvolvimento** | **Intel/Altera Quartus Prime** | Compilação do código, *pin assignment* e geração do arquivo de configuração `.sof`. |

---

## Metodologia

O design do sistema segue uma arquitetura baseada em **Sicronismo de Clock e Memória de Buffer** para garantir o processamento em tempo real dos pixels.

### Máquina de Estados (Finite State Machine - FSM)

A lógica de controle do co-processador gráfico é implementada através de uma **Máquina de Estados Finita (FSM)**. Essa FSM gerencia o ciclo de vida completo de cada operação de redimensionamento, desde a inicialização e leitura dos controles até o processamento de pixel e o *commit* dos dados na memória.

![Image](https://github.com/user-attachments/assets/6e591a19-5860-4a38-a9b6-2a919eb1d5d9)

O ciclo de operação é dividido nos seguintes estados:

| Estado | Função |
| :--- | :--- |
| **IDLE** | Estado inicial e de espera. O processador aguarda o sinal de início de operação, geralmente disparado pela **ativação de um botão ou chave**. |
| **LOAD_OP** | Estado de carregamento da operação. O processador lê os valores atuais dos botões e chaves para determinar **qual algoritmo de zoom (operação)** deve ser executado e qual o **pixel inicial** a ser lido. |
| **READ_PIXEL** | O processador envia o endereço à **Memória** (SDRAM) para ler o valor do pixel (ou bloco de pixels) que será processado. |
| **WAIT_READ** | Estado de espera. É crucial para aguardar o tempo de latência da memória e garantir que o pixel (ou os pixels) solicitados estejam disponíveis antes de iniciar o processamento. |
| **EXECUTE** | O valor do pixel carregado é enviado para a **Unidade Lógica e Aritmética (ULA)**, onde o processamento do zoom (interpolação, replicação, decimação ou média de bloco) é realizado com base na operação definida em `LOAD_OP`. |
| **WRITE** | Estado de escrita. O pixel que acabou de ser processado é escrito de volta na **memória secundária (Frame Buffer)** para a geração da imagem de saída. |
| **NEXT_PIXEL** | O endereço de memória é avançado para que o próximo pixel no ciclo de processamento seja buscado. O sistema verifica se atingiu o fim da imagem. |
| **END_INSTRUCTION** | Estado final da operação de redimensionamento. As *flags* de controle são atualizadas e resetadas, e o sistema retorna ao estado **IDLE** para aguardar a próxima instrução. |

Essa arquitetura sequencial garante que a leitura da memória, o cálculo na ULA e a escrita do resultado sejam realizados de forma coordenada para cada pixel, controlando o fluxo de dados em tempo real.

### Arquitetura do Sistema

<img width="2021" height="1451" alt="Diagrama sem nome drawio(5)" src="https://github.com/user-attachments/assets/500c3d32-2465-4b7f-9732-a1f3de0d7411" />

1.  **Módulo de Controle VGA (VGA Controller):** Gera os sinais de sincronismo padrão VGA (**VGA\_HS**, **VGA\_VS**, **VGA\_CLK**) para a taxa de atualização e resolução desejada (ex: $320 \times 240$ a 25MHz). Este módulo é o mestre do tempo e responsável pela exibição da imagem.
2.  **Módulo de Leitura da Memória:** Endereça e lê os dados de pixel (8-bit) dos blocos de memória da FPGA. O endereço é calculado com um contador de 76800 endereços. As memórias possuem 76800 endereços de 1 Byte, ou seja, 8 bits. Também é usado uma fila para evitar que o vga acesse diretamente a memória. Ela possui 512 espaços de 8 bits.
3.  **Módulo Co-Processador Gráfico (Zoom Processor):** O coração do sistema. Ele recebe o pixel lido da memória e a operação com base no botão e a chave seletora, aplicando a lógica do algoritmo selecionado (Nearest Neighbor, Pixel Replication, Decimação, ou Block Averaging) para calcular o valor do pixel de saída no novo tamanho. Este módulo implementa a lógica combinacional e sequencial específica para cada método.
4.  **Módulo de Saída de Vídeo (VGA Output):** Envia os dados de pixel processados para uma memoria de processamento, para que futuramente eles entrem na fila de exibição.

### Implementação dos Algoritmos de Redimensionamento (Fator 2X)

O fator de escala de **2X** simplifica a lógica de interpolação:

* **Nearest Neighbor (Zoom In):** Para cada pixel original $(x, y)$, quatro pixels de saída $(x', y')$ são mapeados. A lógica utiliza a divisão inteira das coordenadas de saída $(\lfloor x'/2 \rfloor, \lfloor y'/2 \rfloor)$ para determinar o pixel original a ser replicado.

* **Pixel Replication (Zoom In):** Idêntico ao Nearest Neighbor para o fator 2X, onde o valor de cada pixel original é simplesmente replicado em um bloco de $2 \times 2$ pixels na imagem ampliada.

* **Decimação (Zoom Out):** Apenas um pixel a cada bloco de  $2 \times 2$ pixels da imagem original é amostrado e mantido na imagem reduzida. A lógica utiliza o módulo ($\text{mod}$) das coordenadas de leitura para selecionar apenas os pixels com  $x \text{ mod } 2 = 0$ e  $y \text{ mod } 2 = 0$.

* **Block Averaging (Zoom Out):** Para cada pixel de saída $(x', y')$, o módulo calcula a **média aritmética** dos $2 \times 2$  pixels da área correspondente da imagem original. Para garantir um resultado em **8 bits** (sem ponto flutuante), a soma dos 4 pixels é feita e o resultado é deslocado em 2 bits para a direita ($\text{soma} / 4$).

## Explicação dos Clocks (Sinais de Relógio)

O projeto requer o uso de múltiplos sinais de relógio, derivados do **Clock Generator** (Si5350C) a bordo da DE1-SoC, para sincronizar as diferentes operações. A placa DE1-SoC fornece **quatro fontes de clock de 50 MHz** diretamente ao FPGA.

| Sinal de Clock | Frequência | Origem/Propósito | Módulo/Uso | Pin Assignment FPGA |
| :--- | :--- | :--- | :--- | :--- |
| **`CLOCK_50`** | **50 MHz** | Clock primário do sistema. Usado para gerar clocks derivados via **PLL**. | Módulo Top-Level, PLL. | **PIN\_AF14** |
| **`CLK_PIXEL`** | **25.175 MHz** | Frequência padrão para resolução VGA $640 \times 480$ a 60Hz. Gerado a partir de `CLOCK_50` pelo módulo divisor de clock por 2. | Módulo Controlador VGA, Módulos de Processamento. | N/A (reg Output) |
| **`CLOCK_WRITE`** | **75 MHz** | Clock de alta velocidade para a interface com a memória. Gerado internamente por uma **PLL** a partir de `CLOCK_50`. | Controlador SDRAM. |  N/A (PLL Output)|

**Metodologia do Clock:**
1.  O **`CLOCK_50`** é o sinal de referência.
2.  Uma **PLL (Phase-Locked Loop)** é instanciada no Quartus para gerar as frequências de **`CLK_PIXEL`** (para a sincronização VGA) e **`SDRAM_CLK`** (para comunicação com a memória) a partir do `CLOCK_50`.
3.  O sistema é dividido em domínios de clock: o domínio de **50MHz/100MHz** para acesso à memória e lógica interna de alta velocidade, e o domínio de **25.175MHz** para a geração e transmissão dos dados de vídeo.

---

## Mapeamento de Pinos (Pin Assignment - FPGA)

O controle do sistema é feito usando as chaves deslizantes (**SW**) para seleção de modo e os botões de pressão (**KEY**) para acionamento. A saída de vídeo utiliza o conector **VGA** D-SUB (J9).

| Sinal | Direção | Recurso (Board) | FPGA Pin No. |
| :--- | :--- | :--- | :--- |
| **`VGA_R[7:0]`** | Saída | VGA Red (8 bits) | PIN\_A13 - PIN\_F13 (Tabela 3-17) |
| **`VGA_G[7:0]`** | Saída | VGA Green (8 bits) | PIN\_J9 - PIN\_E11 (Tabela 3-17) |
| **`VGA_B[7:0]`** | Saída | VGA Blue (8 bits) | PIN\_B13 - PIN\_J14 (Tabela 3-17) |
| **`VGA_CLK`** | Saída | VGA Clock | PIN\_A11 (Tabela 3-17) |
| **`VGA_HS`** | Saída | VGA Horizontal Sync | PIN\_B11 (Tabela 3-17) |
| **`VGA_VS`** | Saída | VGA Vertical Sync | PIN\_D11 (Tabela 3-17) |
| **`SW[9:0]`** | Entrada | Chaves Deslizantes | PIN\_AE12 - PIN\_AB12 (Tabela 3-7) |
| **`KEY[3:0]`** | Entrada | Botões de Pressão | PIN\_Y16 - PIN\_AA14 (Tabela 3-8) |
| **`CLOCK_50`** | Entrada | Clock 50 MHz | PIN\_AF14 (Tabela 3-6) |
| **`LEDR[9:0]`** | Saída | LEDs Vermelhos | PIN\_Y21 - PIN\_V16 (Tabela 3-9/3-10) |

---

## Compatibilidade HPS (Hard Processor System)

O projeto da lógica do co-processador reside unicamente no **FPGA Fabric**, mas foi desenhado para ser compatível com o **HPS** (ARM Cortex-A9).

A compatibilidade é garantida ao se utilizar o **Lightweight HPS-to-FPGA Bridge** (LW-AXI) para registrar os periféricos e o *Frame Buffer*. O HPS poderá atuar nas próximas etapas lendo os dados de controle (**SW**, **KEY**) e manipulando o *Frame Buffer* na SDRAM, tratando o módulo de Zoom como um periférico de alto desempenho acessível pelo barramento AXI.

## Próximos Passos (Desenvolvimento Futuro)

Este repositório serve como a **Etapa 1** do projeto. As próximas etapas podem incluir:

1.  **Integração com HPS:** Permitir que o HPS carregue imagens de um Micro SD Card para a SDRAM e inicie o processamento gráfico via co-processador FPGA.
2.  **Interface Gráfica (GUI):** Desenvolvimento de uma aplicação Linux/QT no HPS para controlar o zoom e exibir o status do sistema via terminal ou *frame buffer*.
3.  **Algoritmos Avançados:** Implementação de interpolação bilinear ou bicúbica para melhor qualidade de imagem.
