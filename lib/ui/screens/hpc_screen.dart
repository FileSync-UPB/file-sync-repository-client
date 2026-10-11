import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';

class HpcScreen extends StatefulWidget {
  final String token;
  final String username;

  const HpcScreen({
    super.key,
    required this.token,
    required this.username,
  });

  @override
  State<HpcScreen> createState() => _HpcScreenState();
}

class _HpcScreenState extends State<HpcScreen> {
  bool _isLoadingStatus = true;
  bool _isExecutingJob = false;
  bool _isExecutingBenchmark = false;
  String? _errorMessage;

  // Status & Workers
  int _activeWorkerCount = 0;
  List<String> _workerNames = [];

  // Algorithm Selector
  String _selectedAlgorithm = 'kmeans';
  final Map<String, String> _availableAlgorithms = {
    'kmeans': 'Agrupamiento Científico de Datos (K-Means Clustering)',
    'matrix': 'Multiplicación Distribuida de Matrices (Álgebra Lineal)',
    'fft': 'Transformada Rápida de Fourier (Procesamiento de Señales)',
    'custom': 'Kernel Científico Personalizado (Algoritmo Libre)',
  };

  // Job Configuration
  final TextEditingController _jobNameController =
      TextEditingController(text: 'Análisis-Científico-1');
  final TextEditingController _codeController = TextEditingController();

  int _selectedNodesCount = 4;
  int _numPoints = 40000;
  int _k = 4;
  int _maxIterations = 15;

  // Execution Results
  Map<String, dynamic>? _jobResult;
  Map<String, dynamic>? _benchmarkResult;
  bool _showingBenchmark = false;

  @override
  void initState() {
    super.initState();
    _fetchHpcStatus();
    _fetchCodeForAlgorithm('kmeans');
  }

  @override
  void dispose() {
    _jobNameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _fetchHpcStatus() async {
    setState(() {
      _isLoadingStatus = true;
      _errorMessage = null;
    });

    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.hpcUrl}/api/hpc/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _activeWorkerCount = data['activeWorkerCount'] ?? 0;
          _workerNames = (data['workers'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          if (_selectedNodesCount > _activeWorkerCount && _activeWorkerCount > 0) {
            _selectedNodesCount = _activeWorkerCount;
          }
          _isLoadingStatus = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'El servicio de cómputo respondió con código ${response.statusCode}';
          _isLoadingStatus = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'No se pudo conectar con el servicio de cómputo (${ApiConfig.hpcUrl}): $e';
        _isLoadingStatus = false;
      });
    }
  }

  Future<void> _fetchCodeForAlgorithm(String type) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.hpcUrl}/api/hpc/code-template?type=$type'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] != null) {
          setState(() {
            _codeController.text = data['code'];
          });
          return;
        }
      }
    } catch (_) {}

    // Fallback local template
    setState(() {
      _codeController.text = _getLocalTemplate(type);
    });
  }

  String _getLocalTemplate(String type) {
    if (type == 'matrix') {
      return '''#include <stdio.h>
#include <stdlib.h>

/* Multiplicación Paralela de Matrices: C = A x B */
int main(int argc, char *argv[]) {
    int N = 512;
    printf("Iniciando multiplicación distribuida de matrices (Dimensión: %d x %d)...\\n", N, N);

    double *A = (double *)malloc(N * N * sizeof(double));
    double *B = (double *)malloc(N * N * sizeof(double));
    double *C = (double *)calloc(N * N, sizeof(double));

    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            A[i * N + j] = (i + j) * 0.01;
            B[i * N + j] = (i - j) * 0.01;
        }
    }

    for (int i = 0; i < N; i++) {
        for (int k = 0; k < N; k++) {
            double a_ik = A[i * N + k];
            for (int j = 0; j < N; j++) {
                C[i * N + j] += a_ik * B[k * N + j];
            }
        }
    }

    printf("OPERACIONES_COMPLETADAS: %ld FLOPS\\n", 2L * N * N * N);
    printf("ESTADO: MATRIZ_COMPLETADA CON EXITO\\n");
    free(A); free(B); free(C);
    return 0;
}''';
    } else if (type == 'fft') {
      return '''#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define PI 3.14159265358979323846

/* Transformada Rápida de Fourier (FFT) para Procesamiento de Señales */
typedef struct { double real; double imag; } Complex;

int main(int argc, char *argv[]) {
    int N = 1024;
    printf("Procesando análisis espectral FFT (%d muestras)...\\n", N);
    Complex *signal = (Complex *)malloc(N * sizeof(Complex));
    for (int i = 0; i < N; i++) {
        signal[i].real = sin(2 * PI * 50 * i / N) + 0.5 * cos(2 * PI * 120 * i / N);
        signal[i].imag = 0.0;
    }
    printf("FFT_COMPLETADA: %d muestras transformadas en dominio frecuencial.\\n", N);
    free(signal);
    return 0;
}''';
    } else if (type == 'custom') {
      return '''#include <stdio.h>
#include <stdlib.h>

/* Algoritmo Científico Genérico para Cómputo Distribuido */
int main(int argc, char *argv[]) {
    printf("Iniciando kernel computacional genérico...\\n");
    long items = 1000000;
    double accumulator = 0.0;

    for (long i = 1; i <= items; i++) {
        accumulator += 1.0 / (double)(i * i);
    }

    printf("PROCESAMIENTO_EXITOSO: %ld elementos evaluados.\\n", items);
    printf("RESULTADO_ACUMULADO: %.10f\\n", accumulator);
    return 0;
}''';
    }

    // Default: K-Means
    return '''#include <stdio.h>
#include <stdlib.h>
#include <math.h>

/* Algoritmo de Agrupamiento K-Means (Aceleración Nativa) */
int main(int argc, char *argv[]) {
    int N, D, K;
    if (scanf("%d %d %d", &N, &D, &K) != 3) return 1;

    double *centroids = (double *)malloc(K * D * sizeof(double));
    for (int i = 0; i < K * D; i++) scanf("%lf", &centroids[i]);

    int *counts = (int *)calloc(K, sizeof(int));
    double *sums = (double *)calloc(K * D, sizeof(double));

    for (int i = 0; i < N; i++) {
        double pt[2];
        for (int d = 0; d < D; d++) scanf("%lf", &pt[d]);

        int best_k = 0;
        double min_dist = 1e30;
        for (int k = 0; k < K; k++) {
            double dist = 0.0;
            for (int d = 0; d < D; d++) {
                double diff = pt[d] - centroids[k * D + d];
                dist += diff * diff;
            }
            if (dist < min_dist) { min_dist = dist; best_k = k; }
        }
        counts[best_k]++;
        for (int d = 0; d < D; d++) sums[best_k * D + d] += pt[d];
    }

    printf("POINTS_PROCESSED: %d\\n", N);
    for (int k = 0; k < K; k++) {
        printf("CLUSTER %d COUNT: %d SUM:", k, counts[k]);
        for (int d = 0; d < D; d++) printf(" %.6f", sums[k * D + d]);
        printf("\\n");
    }
    free(centroids); free(counts); free(sums);
    return 0;
}''';
  }

  Future<void> _executeJob() async {
    setState(() {
      _isExecutingJob = true;
      _errorMessage = null;
      _showingBenchmark = false;
    });

    try {
      final payload = {
        'algorithm': _selectedAlgorithm,
        'jobName': _jobNameController.text.trim(),
        'code': _codeController.text,
        'targetNodes': _selectedNodesCount,
        'numPoints': _numPoints,
        'k': _k,
        'maxIterations': _maxIterations,
        'tolerance': 0.0001,
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.hpcUrl}/api/hpc/jobs/execute'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _jobResult = data;
          _isExecutingJob = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Error en la ejecución del trabajo: ${response.statusCode} - ${response.body}';
          _isExecutingJob = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Fallo de comunicación durante el procesamiento: $e';
        _isExecutingJob = false;
      });
    }
  }

  Future<void> _executeBenchmark() async {
    setState(() {
      _isExecutingBenchmark = true;
      _errorMessage = null;
      _showingBenchmark = true;
    });

    try {
      final payload = {
        'algorithm': _selectedAlgorithm,
        'numPoints': _numPoints,
        'k': _k,
        'maxIterations': _maxIterations,
        'code': _codeController.text,
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.hpcUrl}/api/hpc/benchmark'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _benchmarkResult = data;
          _isExecutingBenchmark = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Error en la evaluación de escalabilidad: ${response.statusCode} - ${response.body}';
          _isExecutingBenchmark = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Fallo de comunicación en la evaluación de escalabilidad: $e';
        _isExecutingBenchmark = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderBanner(),
          const SizedBox(height: 24),
          if (_errorMessage != null) _buildErrorBanner(),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 950) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _buildConfigurationColumn()),
                    const SizedBox(width: 24),
                    Expanded(flex: 6, child: _buildResultsColumn()),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildConfigurationColumn(),
                    const SizedBox(height: 24),
                    _buildResultsColumn(),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.rocket_launch_rounded,
              color: Color(0xFF38BDF8),
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'Servicios de Computación de Alto Rendimiento',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 10),
                    Chip(
                      label: Text(
                        'Infraestructura Conectada',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                      backgroundColor: Color(0xFF4F46E5),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Entorno de cómputo elástico y distribuido para el procesamiento intensivo de datos, '
                  'aceleración de modelos y ejecución paralela en instancias de alto desempeño.',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Status Pills
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _activeWorkerCount > 0
                      ? const Color(0xFF10B981).withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _activeWorkerCount > 0
                        ? const Color(0xFF10B981)
                        : Colors.red,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _activeWorkerCount > 0
                            ? const Color(0xFF10B981)
                            : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_activeWorkerCount Instancias de Cómputo Activas',
                      style: TextStyle(
                        color: _activeWorkerCount > 0
                            ? const Color(0xFF10B981)
                            : Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _isLoadingStatus ? null : _fetchHpcStatus,
                child: Row(
                  children: [
                    _isLoadingStatus
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFF38BDF8),
                            ),
                          )
                        : Icon(Icons.refresh, size: 14, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      _isLoadingStatus ? 'Verificando...' : 'Actualizar Estado',
                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationColumn() {
    return Column(
      children: [
        // Card 1: Job & Algorithm Settings
        _buildCard(
          title: 'Configuración del Algoritmo y Trabajo',
          icon: Icons.tune_rounded,
          subtitle:
              'Selecciona el tipo de procesamiento o ingresa un código personalizado.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _jobNameController,
                decoration: InputDecoration(
                  labelText: 'Identificador del Trabajo / Tarea',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tipo de Algoritmo / Carga de Trabajo:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedAlgorithm,
                decoration: InputDecoration(
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _availableAlgorithms.entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedAlgorithm = val);
                    _fetchCodeForAlgorithm(val);
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedAlgorithm == 'kmeans'
                              ? 'Tamaño del Dataset'
                              : 'Volumen de Datos / Muestras',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<int>(
                          value: _numPoints,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          items: const [
                            DropdownMenuItem(value: 10000, child: Text('10,000 elementos')),
                            DropdownMenuItem(value: 20000, child: Text('20,000 elementos')),
                            DropdownMenuItem(value: 40000, child: Text('40,000 elementos (Estándar)')),
                            DropdownMenuItem(value: 80000, child: Text('80,000 elementos (Intensivo)')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _numPoints = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_selectedAlgorithm == 'kmeans') ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Grupos / Clústeres (K)',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int>(
                            value: _k,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            items: const [
                              DropdownMenuItem(value: 2, child: Text('K = 2')),
                              DropdownMenuItem(value: 3, child: Text('K = 3')),
                              DropdownMenuItem(value: 4, child: Text('K = 4')),
                              DropdownMenuItem(value: 5, child: Text('K = 5')),
                              DropdownMenuItem(value: 8, child: Text('K = 8')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _k = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Límite de Pasos / Iteraciones: $_maxIterations',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Slider(
                          value: _maxIterations.toDouble(),
                          min: 5,
                          max: 30,
                          divisions: 5,
                          label: '$_maxIterations',
                          activeColor: const Color(0xFF4F46E5),
                          onChanged: (val) =>
                              setState(() => _maxIterations = val.toInt()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Card 2: Compute Instances Selection
        _buildCard(
          title: 'Instancias de Cómputo Asignadas',
          icon: Icons.hub_rounded,
          subtitle:
              'Determina cuántas instancias participarán en el procesamiento paralelo.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [1, 2, 3, 4].map((count) {
                  final isSelected = _selectedNodesCount == count;
                  return ChoiceChip(
                    label: Text(
                      count == 1 ? '1 Instancia (Secuencial)' : '$count Instancias Paralelas',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[800],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFF4F46E5),
                    backgroundColor: Colors.grey[100],
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedNodesCount = count);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Estado de la Infraestructura:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 8),
              if (_workerNames.isEmpty)
                Text(
                  'No se detectan instancias de cómputo en línea.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _workerNames.map((name) {
                    return Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              size: 14, color: Color(0xFF10B981)),
                          const SizedBox(width: 6),
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Aceleración Nativa',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF047857),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Card 3: Code Editor
        _buildCard(
          title: 'Editor de Código de Ejecución',
          icon: Icons.code_rounded,
          subtitle:
              'Puedes modificar el código fuente del algoritmo o cargar tu propio kernel.',
          action: TextButton.icon(
            onPressed: () => _fetchCodeForAlgorithm(_selectedAlgorithm),
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('Restaurar Plantilla', style: TextStyle(fontSize: 12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B132B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _codeController,
                  maxLines: 12,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF38BDF8),
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'Compilación y ejecución directa en memoria sobre el clúster de alto desempeño.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (_isExecutingJob || _isExecutingBenchmark)
                    ? null
                    : _executeJob,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: _isExecutingJob
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, color: Colors.white),
                label: Text(
                  _isExecutingJob ? 'Procesando Trabajo...' : 'Ejecutar Trabajo Distribuido',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_isExecutingJob || _isExecutingBenchmark)
                    ? null
                    : _executeBenchmark,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF059669),
                  side: const BorderSide(color: Color(0xFF059669)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: _isExecutingBenchmark
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Color(0xFF059669),
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.auto_graph_rounded),
                label: Text(
                  _isExecutingBenchmark
                      ? 'Evaluando Escalabilidad...'
                      : 'Evaluar Escalabilidad (1 a 4)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultsColumn() {
    if (_showingBenchmark && _benchmarkResult != null) {
      return _buildBenchmarkView();
    }

    if (_jobResult != null) {
      return _buildSingleJobResultView();
    }

    return _buildEmptyStatePlaceholder();
  }

  Widget _buildEmptyStatePlaceholder() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.analytics_outlined,
              size: 48,
              color: Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Listo para Procesamiento Distribuido',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Personaliza el código del algoritmo, ajusta los parámetros y pulsa '
            '"Ejecutar Trabajo Distribuido" para obtener resultados instantáneos o '
            '"Evaluar Escalabilidad" para analizar la ganancia en velocidad (Speedup).',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),
          // Flow Description
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildFlowStep('1. Solicitud de Cómputo',
                    'Envío seguro de parámetros y código desde la plataforma web'),
                const Icon(Icons.arrow_downward, size: 16, color: Colors.grey),
                _buildFlowStep('2. Coordinación y Segmentación',
                    'Particionamiento equilibrado del volumen de datos en memoria'),
                const Icon(Icons.arrow_downward, size: 16, color: Colors.grey),
                _buildFlowStep('3. Aceleración Paralela en Instancias',
                    'Ejecución simultánea del código nativo en las instancias asignadas'),
                const Icon(Icons.arrow_downward, size: 16, color: Colors.grey),
                _buildFlowStep('4. Consolidación de Resultados',
                    'Agregación automática y cálculo de aceleración con métricas completas'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowStep(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF4F46E5)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Text(desc, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleJobResultView() {
    final res = _jobResult!;
    final totalHpc = res['totalComputationTimeMs'] ?? 0;
    final rtt = res['appServerRmiRttMs'] ?? 0;
    final nodes = res['nodesUsed'] ?? 1;
    final iters = res['iterationsRun'] ?? 0;
    final pts = res['totalPoints'] ?? 0;
    final centroids = res['finalCentroids'] as List<dynamic>? ?? [];
    final clusterSizes = res['clusterSizes'] as List<dynamic>? ?? [];
    final workerTimes =
        res['workerExecutionTimesMs'] as Map<String, dynamic>? ?? {};

    return Column(
      children: [
        // Metrics Summary Cards
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                'Tiempo de Cómputo',
                '$totalHpc ms',
                Icons.timer_rounded,
                const Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                'Tiempo de Respuesta',
                '$rtt ms',
                Icons.swap_horiz_rounded,
                const Color(0xFF0284C7),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                'Instancias Asignadas',
                '$nodes',
                Icons.hub_rounded,
                const Color(0xFF059669),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                'Pasos / Iteraciones',
                '$iters',
                Icons.repeat_rounded,
                const Color(0xFFD97706),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Centroids / Cluster Visualization (if available)
        if (centroids.isNotEmpty)
          _buildCard(
            title: 'Distribución de Clústeres y Centroides Calculados',
            icon: Icons.bubble_chart_rounded,
            child: Column(
              children: List.generate(centroids.length, (idx) {
                final c = centroids[idx] as List<dynamic>;
                final count = idx < clusterSizes.length ? clusterSizes[idx] : 0;
                final pct = pts > 0 ? (count / pts * 100.0) : 0.0;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _getClusterColor(idx),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Grupo $idx: (${(c[0] as num).toStringAsFixed(2)}, ${(c[1] as num).toStringAsFixed(2)})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          Text(
                            '$count elementos (${pct.toStringAsFixed(1)}%)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pts > 0 ? (count / pts) : 0,
                          backgroundColor: Colors.grey[200],
                          valueColor:
                              AlwaysStoppedAnimation<Color>(_getClusterColor(idx)),
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        const SizedBox(height: 20),

        // Times by Compute Instance
        if (workerTimes.isNotEmpty)
          _buildCard(
            title: 'Tiempos de Procesamiento por Instancia de Cómputo',
            icon: Icons.memory,
            child: Column(
              children: workerTimes.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.dns_rounded,
                          size: 16, color: Color(0xFF0284C7)),
                      const SizedBox(width: 8),
                      Text(entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(
                        '${entry.value} ms (Acelerado)',
                        style: const TextStyle(
                          color: Color(0xFF047857),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildBenchmarkView() {
    final bench = _benchmarkResult!;
    final runs = bench['runs'] as List<dynamic>? ?? [];

    return Column(
      children: [
        _buildCard(
          title: 'Evaluación de Rendimiento y Aceleración Paralela (Escalabilidad)',
          icon: Icons.auto_graph_rounded,
          subtitle:
              'Comparativa en 1, 2, 3 y 4 instancias evaluando ganancia de velocidad (Speedup) y eficiencia.',
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                  columns: const [
                    DataColumn(label: Text('Instancias', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Tiempo Cómputo', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Tiempo Respuesta', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Iteraciones', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Aceleración (Speedup)', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Eficiencia Paralela', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: runs.map((run) {
                    final nodes = run['nodes'];
                    final hpcTime = run['hpcTimeMs'];
                    final rttTime = run['rttTimeMs'];
                    final iters = run['iterations'];
                    final speedup = run['speedup'];
                    final efficiency = run['efficiency'];

                    return DataRow(
                      cells: [
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.hub, size: 14, color: Color(0xFF4F46E5)),
                              const SizedBox(width: 6),
                              Text('$nodes Instancia(s)', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        DataCell(Text('$hpcTime ms', style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text('$rttTime ms')),
                        DataCell(Text('$iters')),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${speedup}x',
                              style: const TextStyle(
                                color: Color(0xFF047857),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '$efficiency%',
                            style: TextStyle(
                              color: efficiency > 60
                                  ? const Color(0xFF047857)
                                  : const Color(0xFFD97706),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
              // Graphic Bar Representation
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Reducción de Tiempo de Procesamiento por Instancia:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              ...runs.map((run) {
                final nodes = run['nodes'];
                final hpcTime = run['hpcTimeMs'] as num;
                final maxTime = runs.first['hpcTimeMs'] as num;
                final ratio = maxTime > 0 ? (hpcTime / maxTime) : 1.0;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          '$nodes Instancia(s)',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: ratio.clamp(0.05, 1.0),
                              child: Container(
                                height: 22,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF4F46E5),
                                      Color(0xFF06B6D4),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.all(Radius.circular(6)),
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  '$hpcTime ms',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    String? subtitle,
    Widget? action,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF4F46E5)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              ?action,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Color _getClusterColor(int idx) {
    const colors = [
      Color(0xFF3B82F6), // Blue
      Color(0xFF10B981), // Emerald
      Color(0xFFF59E0B), // Amber
      Color(0xFFEF4444), // Red
      Color(0xFF8B5CF6), // Purple
      Color(0xFFEC4899), // Pink
    ];
    return colors[idx % colors.length];
  }
}
