# 🤝 Guia de Contribuição

Obrigado por considerar contribuir para o **Pedidos Veloz**! Este documento fornece diretrizes e instruções para contribuir ao projeto.

## 📋 Código de Conduta

Esperamos que todos os contribuidores sigam nosso código de conduta. Seja respeitoso e inclusivo.

## 🚀 Como Contribuir

### 1. Fork e Clone
\\\powershell
git clone https://github.com/seu-usuario/pedidos-veloz.git
cd pedidos-veloz
git remote add upstream https://github.com/Devan-M/pedidos-veloz.git
\\\

### 2. Criar Branch
\\\powershell
git checkout -b feature/sua-feature
\\\

Use nomes descritivos:
- \eature/adicionar-autenticacao\
- \ix/corrigir-bug-pagamento\
- \docs/melhorar-readme\
- \	est/aumentar-cobertura\

### 3. Fazer Alterações

Siga os padrões do projeto:
- **Node.js**: ESLint + Prettier
- **Python**: PEP 8 + Black

### 4. Testar Localmente

**Orders Service**
\\\powershell
cd services/orders-service
npm install
npm test
npm run lint
\\\

**Inventory Service**
\\\powershell
cd services/inventory-service
npm install
npm test
npm run lint
\\\

**Payments Service**
\\\powershell
cd services/payments-service
pip install -r requirements.txt
python -m pytest tests/ -v --cov=app
\\\

### 5. Commit com Mensagem Clara

Usamos [Conventional Commits](https://www.conventionalcommits.org/):

\\\
feat: adicionar nova funcionalidade
fix: corrigir bug específico
test: adicionar testes unitários
ci: atualizar pipeline
docs: atualizar documentação
refactor: melhorar código
chore: tarefas de manutenção
perf: melhorias de performance
\\\

**Exemplos:**
\\\powershell
git commit -m "feat: adicionar autenticação JWT no API Gateway"
git commit -m "fix: corrigir race condition em Orders Service"
git commit -m "test: aumentar cobertura de Payments Service para 80%"
git commit -m "docs: adicionar guia de deployment em Kubernetes"
\\\

### 6. Push e Pull Request

\\\powershell
git push origin feature/sua-feature
\\\

Abra um Pull Request no GitHub com:
- **Título**: Descritivo e seguindo Conventional Commits
- **Descrição**: Explique o quê e por quê
- **Referências**: Link issues relacionadas (#123)
- **Checklist**: Marque itens completados

**Template PR:**
\\\markdown
## Descrição
Breve descrição do que foi alterado.

## Tipo de Mudança
- [ ] Bug fix
- [ ] Nova feature
- [ ] Breaking change
- [ ] Documentação

## Como Testar
Passos para testar as alterações.

## Checklist
- [ ] Testes passando
- [ ] Cobertura mantida/aumentada
- [ ] Lint passando
- [ ] Documentação atualizada
- [ ] Commit messages seguem padrão
\\\

## 📊 Padrões de Código

### Node.js (Orders, Inventory, API Gateway)

**Estrutura de arquivo:**
\\\
src/
├── controllers/
├── services/
├── models/
├── middleware/
├── routes/
└── utils/

__tests__/
├── unit/
├── integration/
└── fixtures/
\\\

**Exemplo de teste:**
\\\javascript
describe('OrdersService', () => {
  it('should create order with valid data', async () => {
    const order = await ordersService.create({
      customerId: '123',
      items: [{ productId: '456', quantity: 2 }]
    });

    expect(order).toHaveProperty('id');
    expect(order.status).toBe('pending');
  });
});
\\\

### Python (Payments Service)

**Estrutura de arquivo:**
\\\
app.py
requirements.txt
tests/
├── __init__.py
├── test_payments.py
└── fixtures/
\\\

**Exemplo de teste:**
\\\python
def test_create_payment_success(client, mock_db):
    payment_data = {
        'order_id': 'order-123',
        'amount': 199.98,
        'payment_method': 'credit_card'
    }

    response = client.post('/payments', json=payment_data)

    assert response.status_code == 201
    assert response.json['status'] == 'pending'
\\\

## 🧪 Requisitos de Teste

- **Cobertura mínima**: 50% para novas features
- **Testes unitários**: Obrigatório
- **Testes de integração**: Para features críticas
- **Todos os testes devem passar** antes do merge

## 📝 Documentação

Atualize documentação para:
- Novas features
- Mudanças em APIs
- Novas variáveis de ambiente
- Instruções de setup

## 🔍 Revisão de Código

Esperamos que PRs sejam revisados por pelo menos 1 mantenedor.

**O que procuramos:**
- ✅ Código limpo e bem estruturado
- ✅ Testes adequados
- ✅ Documentação clara
- ✅ Sem breaking changes sem discussão
- ✅ Performance considerada

## 🐛 Reportar Bugs

Abra uma [Issue](https://github.com/Devan-M/pedidos-veloz/issues) com:

**Template:**
\\\markdown
## Descrição
Descrição clara do bug.

## Passos para Reproduzir
1. Passo 1
2. Passo 2
3. Passo 3

## Comportamento Esperado
O que deveria acontecer.

## Comportamento Atual
O que está acontecendo.

## Ambiente
- OS: Windows 10
- Node.js: 18.0.0
- Python: 3.11.0
- Docker: 24.0.0

## Logs
\\\
Cole logs relevantes aqui
\\\
\\\

## 💡 Sugerir Features

Abra uma [Discussion](https://github.com/Devan-M/pedidos-veloz/discussions) ou [Issue](https://github.com/Devan-M/pedidos-veloz/issues) com:

- **Descrição**: O que você quer adicionar
- **Motivação**: Por que é importante
- **Exemplos**: Como seria usado

## 📚 Recursos Úteis

- [Conventional Commits](https://www.conventionalcommits.org/)
- [Jest Testing](https://jestjs.io/)
- [Pytest Documentation](https://docs.pytest.org/)
- [Express.js Guide](https://expressjs.com/)
- [Flask Documentation](https://flask.palletsprojects.com/)

## 🎓 Aprendendo o Projeto

1. Leia o [README.md](../README.md)
2. Explore a estrutura em \services/\
3. Rode os testes localmente
4. Leia issues abertas e PRs
5. Participe de discussions

## ✨ Boas Práticas

- Commits pequenos e focados
- Uma feature por branch
- Rebase antes de fazer push
- Squash commits relacionados
- Escreva mensagens de commit descritivas

## 🚫 O que NÃO fazer

- ❌ Não fazer push direto em \main\
- ❌ Não mergear seu próprio PR
- ❌ Não ignorar testes falhando
- ❌ Não fazer grandes refactors sem discussão
- ❌ Não adicionar dependências sem justificar

## 📞 Dúvidas?

- Abra uma [Discussion](https://github.com/Devan-M/pedidos-veloz/discussions)
- Comente em uma [Issue](https://github.com/Devan-M/pedidos-veloz/issues)
- Veja a [Documentação](../docs/)

---

**Obrigado por contribuir! 🙏**
