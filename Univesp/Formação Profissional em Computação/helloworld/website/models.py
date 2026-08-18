from django.db import models

# Create your models here.
class AlunoUnivesp(models.Model):
    nome = models.CharField(
        max_length=255,
        null = False,
        blank = False
    )
    sobrenome = models.CharField(
        max_length=255,
        null = False,
        blank = False
    )
    matricula = models.CharField(
        max_length=14,
        null =False,
        blank = False
    )
    objects = models.Manager()