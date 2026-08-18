from django.shortcuts import render
from .models import AlunoUnivesp

def lista_alunos(request):
    alunos = AlunoUnivesp.objects.all()
    return render(request, 'alunos.html', {'alunos': alunos})