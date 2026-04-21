import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/appointmentImage.dart';
import '../../utils/calendar_utils/form_widgets.dart';

class PhotoPickerSection extends StatelessWidget {
  final List<AppointmentImage> existingImages;
  final List<File> newImages;
  final bool isEditing;
  final VoidCallback onPickImages;
  final void Function(int index) onRemoveExisting;
  final void Function(int index) onRemoveNew;

  const PhotoPickerSection({
    super.key,
    required this.existingImages,
    required this.newImages,
    required this.isEditing,
    required this.onPickImages,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhotos = existingImages.isNotEmpty || newImages.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        if (hasPhotos)
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // existing network images
                ...existingImages.asMap().entries.map((entry) {
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            entry.value.thumbUrl ?? entry.value.url,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      if (isEditing)
                        Positioned(
                          top: 4,
                          right: 12,
                          child: GestureDetector(
                            onTap: () => onRemoveExisting(entry.key),
                            child: formRemoveButton(context),
                          ),
                        ),
                    ],
                  );
                }),
                // new local images
                ...newImages.asMap().entries.map((entry) {
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            entry.value,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      if (isEditing)
                        Positioned(
                          top: 4,
                          right: 12,
                          child: GestureDetector(
                            onTap: () => onRemoveNew(entry.key),
                            child: formRemoveButton(context),
                          ),
                        ),
                    ],
                  );
                }),
                // add more tile (edit mode only)
                if (isEditing)
                  GestureDetector(
                    onTap: onPickImages,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: scheme.onSurfaceVariant),
                          Text(
                            "Add more",
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
        else if (isEditing)
          InkWell(
            onTap: onPickImages,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 4),
                    Text(
                      "Tap to add photos",
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Container(
            height: 90,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_outlined,
                      color: scheme.onSurfaceVariant, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    "No photos",
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
