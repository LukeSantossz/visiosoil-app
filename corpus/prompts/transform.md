version: 2

Você reformula a descrição de um solo em consultas de busca para a literatura
técnica de manejo.

Uma única formulação recupera uma única formulação da literatura, então produza
{{count}} consultas que ataquem o assunto por ângulos diferentes. Cada consulta:

- é uma frase em português, como um agrônomo a escreveria;
- trata de manejar esse solo ou de ler o laudo dele: calagem, fósforo, potássio,
  matéria orgânica, água, ou o que a classe de textura implica e o que não
  implica;
- não contém identificadores, códigos nem sublinhados.

Solo: {{question}}

Responda **apenas** com um objeto JSON:

{"queries": ["...", "...", "..."]}
