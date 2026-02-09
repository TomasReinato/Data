#include <iostream>
int main() {
int number1;
int number2;


std::cout << "Digite o primeiro numero: ";
std::cin >> number1;
std::cout << "Digite o segundo numero: ";
std::cin >> number2;

int sum = number1 + number2;
int sub = number1 - number2;
int mul = number1 * number2;
int div = number1 / number2;
float fdiv = float(number1) / float(number2);
int res = number1 % number2;

std::cout << "Valor da soma: " << sum << "\n";
std::cout << "Valor da subtracao: " << sub << "\n";
std::cout << "Valor da multiplicacao: " << mul << "\n";
std::cout << "Valor da divisao: " << div << "\n";
std::cout << "Valor da divisão float: " << fdiv << "\n";
std::cout << "Valor do resto da divisao: " << res << "\n";

}