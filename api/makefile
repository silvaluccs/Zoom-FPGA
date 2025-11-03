# Definindo variáveis de compilação
CC = gcc                    # Compilador C
AS = as                      # Compilador Assembly
CFLAGS = -Wall -g            # Flags de compilação C (exemplo: -Wall para mostrar todos os avisos)
ASFLAGS =                    # Flags para o assembler (não precisa de muitas para este caso)
LDFLAGS =                    # Flags de linkagem (não estamos usando flags específicas)

# Definindo os arquivos fonte
SRC_C = main.c               # Arquivo C principal
SRC_ASM = api.s               # Arquivo Assembly
OBJ_C = main.o               # Arquivo objeto do C
OBJ_ASM = api.o               # Arquivo objeto do Assembly
EXEC = main          # Nome do executável

# Alvo padrão: compilar e gerar o executável
all: $(EXEC)

# Como compilar o código C
$(OBJ_C): $(SRC_C) api.h
	$(CC) $(CFLAGS) -c -o $@ $<

# Como compilar o código Assembly
$(OBJ_ASM): $(SRC_ASM)
	$(AS) -o $@ $<

# Como linkar os objetos para gerar o executável
$(EXEC): $(OBJ_C) $(OBJ_ASM)
	$(CC) $(LDFLAGS) -o $@ $^

# Limpar arquivos gerados (como .o e o executável)
clean:
	rm -f $(OBJ_C) $(OBJ_ASM) $(EXEC)

# Alvo para testar a execução do programa
run: $(EXEC)
	./$(EXEC)

# Informações de ajuda
help:
	@echo "Comandos disponíveis:"
	@echo "  make        - Compila e gera o executável"
	@echo "  make clean  - Remove arquivos objetos e o executável"
	@echo "  make run    - Executa o programa gerado"
	@echo "  make help   - Exibe este texto de ajuda"

