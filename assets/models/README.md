# ISLA — Modelos TFLite

Este directorio contiene los modelos `.tflite` necesarios para el pipeline de inferencia on-device.

## Archivos esperados

| Archivo | Tipo | Tamaño aprox. | Propósito |
|---------|------|---------------|-----------|
| `classifier.tflite` | MLP (TFLite) | ~45 KB | Clasifica landmarks → gesto individual (Fase 3) |
| `lstm.tflite` | LSTM (TFLite) | Variable | Decodifica secuencia de gestos → frase (Fase 3) |

## Referencia

Basado en el pipeline de **SignSpeak** (dev.to/noor_y) y la exploración de viabilidad
(`sdd/viabilidad-signgemma-mediapipe/explore`). El MLP clasificador se entrena sobre
126 features por frame (21 landmarks × 2 manos × 3 coordenadas). El LSTM maneja la
ventana temporal de 1–2 segundos para decodificación secuencial.

## Notas

- Los modelos se agregan en Fase 3 (Inference layer). Por ahora este placeholder
  asegura que `pubspec.yaml` tenga la ruta `assets/models/` declarada.
- Formato: TFLite FlatBuffer, cuantizados a INT8 para reducir tamaño y latencia.
- Fallback: si no se encuentran los archivos, el sistema reporta error sin crashear
  (spec `gesture-classifier` edge case).
