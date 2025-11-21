# Definindo o Compilador (gcc é o padrão, mas é bom ser explícito)
CC = gcc

# Nome do executável final
TARGET = main

# Arquivos objeto necessários (gerados a partir dos arquivos .c e .s)
OBJS = main.o biblioteca.o

# -----------------------------------------------------------------------------
# Regra principal para construir o executável
# Esta regra depende de todos os arquivos objeto.
$(TARGET): $(OBJS)
	# Passo 3: Ligação (Linking) - Cria o executável final 'main'
	$(CC) -o $(TARGET) $(OBJS)
	@echo "--- Executável '$(TARGET)' criado com sucesso. ---"

# Regra implícita: Como compilar main.o a partir de main.c (arquivo C)
# main.o: main.c
#	$(CC) -c -o main.o main.c
# O make já sabe como fazer isso, mas podemos ser explícitos:
main.o: main.c
	# Passo 2: Compilação do arquivo C 'main.c' para 'main.o'
	$(CC) -c -o $@ $<

# Regra para compilar biblioteca.o a partir de biblioteca.s (arquivo Assembly)
biblioteca.o: biblioteca.s
	# Passo 1: Compilação do arquivo Assembly 'biblioteca.s' para 'biblioteca.o'
	$(CC) -c -o $@ $<

# -----------------------------------------------------------------------------
# Regra para executar o programa.
# Usa 'sudo' conforme solicitado.
.PHONY: run
run: $(TARGET)
	@echo "--- Executando o programa '$(TARGET)' com 'sudo ./main'... ---"
	sudo ./$(TARGET)

# Regra para limpar os arquivos gerados (objetos e executável)
.PHONY: clean
clean:
	# Remove os arquivos objeto (.o) e o executável (main)
	rm -f $(OBJS) $(TARGET)
	@echo "--- Arquivos objeto e executável removidos. ---"
