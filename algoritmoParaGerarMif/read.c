// peguei o codigo de https://www.geeksforgeeks.org/reading-pgm-image-c/
// para ler um arquivo .pgm
// e modifiquei para gerar um arquivo .mif

#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct PGMImage {
  char pgmType[3];
  unsigned char **data;
  unsigned int width;
  unsigned int height;
  unsigned int maxValue;
} PGMImage;

void ignoreComments(FILE *fp) {
  int ch;
  char line[100];

  while ((ch = fgetc(fp)) != EOF && isspace(ch))
    ;

  if (ch == '#') {
    fgets(line, sizeof(line), fp);
    ignoreComments(fp);
  } else
    fseek(fp, -1, SEEK_CUR);
}

bool openPGM(PGMImage *pgm, const char *filename) {
  FILE *pgmfile = fopen(filename, "rb");

  if (pgmfile == NULL) {
    printf("File does not exist\n");
    return false;
  }

  ignoreComments(pgmfile);
  fscanf(pgmfile, "%s", pgm->pgmType);

  if (strcmp(pgm->pgmType, "P5")) {
    fprintf(stderr, "Wrong file type!\n");
    exit(EXIT_FAILURE);
  }

  ignoreComments(pgmfile);

  fscanf(pgmfile, "%d %d", &(pgm->width), &(pgm->height));

  ignoreComments(pgmfile);

  fscanf(pgmfile, "%d", &(pgm->maxValue));
  ignoreComments(pgmfile);

  pgm->data = malloc(pgm->height * sizeof(unsigned char *));

  if (pgm->pgmType[1] == '5') {

    fgetc(pgmfile);

    for (int i = 0; i < pgm->height; i++) {
      pgm->data[i] = malloc(pgm->width * sizeof(unsigned char));

      if (pgm->data[i] == NULL) {
        fprintf(stderr, "malloc failed\n");
        exit(1);
      }

      fread(pgm->data[i], sizeof(unsigned char), pgm->width, pgmfile);
    }
  }

  fclose(pgmfile);

  return true;
}

void printImageDetails(PGMImage *pgm, const char *filename) {
  FILE *pgmfile = fopen(filename, "rb");

  char *ext = strrchr(filename, '.');

  if (!ext)
    printf("No extension found"
           "in file %s",
           filename);
  else
    printf("File format"
           "    : %s\n",
           ext + 1);

  printf("PGM File type  : %s\n", pgm->pgmType);

  // Print type of PGM file, in ascii
  // and binary format
  if (!strcmp(pgm->pgmType, "P2"))
    printf("PGM File Format:"
           "ASCII\n");
  else if (!strcmp(pgm->pgmType, "P5"))
    printf("PGM File Format:"
           " Binary\n");

  printf("Width of img   : %d px\n", pgm->width);
  printf("Height of img  : %d px\n", pgm->height);
  printf("Max Gray value : %d\n", pgm->maxValue);

  fclose(pgmfile);
}

void writeMIF(PGMImage *pgm) {
  FILE *filept;

  filept = fopen("memory.mif", "w");

  fprintf(filept, "WIDTH=8;\n");
  fprintf(filept, "DEPTH=76800;\n\n");
  fprintf(filept, "ADDRESS_RADIX=HEX;\n");
  fprintf(filept, "DATA_RADIX=HEX;\n\n");
  fprintf(filept, "CONTENT BEGIN\n");

  int andress = 0;
  for (int i = 0; i < pgm->height; i++) {
    for (int j = 0; j < pgm->width; j++) {

      fprintf(filept, " %X : %02X;\n", andress++, pgm->data[i][j]);
    }
  }

  fprintf(filept, "END;\n");

  fclose(filept);
}

int main(int argc, char const *argv[]) {
  PGMImage *pgm = malloc(sizeof(PGMImage));
  const char *ipfile;

  if (argc == 2)
    ipfile = argv[1];
  else
    ipfile = "gfg_logo.pgm";

  printf("\tip file : %s\n", ipfile);

  // Process the image and print
  // its details
  if (openPGM(pgm, ipfile)) {
    printImageDetails(pgm, ipfile);
    writeMIF(pgm);
  }

  return 0;
}
