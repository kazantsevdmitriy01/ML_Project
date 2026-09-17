%% =========================================================
%  CLOUD CLASSIFIER - Predict New Images
%
%  Usage:
%    1. Make sure you have run main_train.m first
%    2. Set MODEL_FILE to your saved .mat file
%    3. Set IMAGE_PATH to the image you want to classify
%       (can be a single file or a folder of images)
% =========================================================

clc; clear; close all;

%% ---- CONFIGURATION --------------------------------------------------
% Path to your saved model from main_train.m
MODEL_FILE = 'saved_models/cloud_model_extended_20260314_2304';   % << UPDATE THIS

% Path to image(s) to classify — can be:
%   - A single image:  'my_cloud.jpg'
%   - A folder:        'new_images/'
IMAGE_PATH = ['virg.jpg'];

IMAGE_SIZE = [224 224 3];

%% ---- LOAD MODEL -----------------------------------------------------
fprintf('Loading model from: %s\n', MODEL_FILE);
data = load(MODEL_FILE);
% Handle both base model and extended model variable names
if isfield(data, 'trainedNet')
    net = data.trainedNet;
elseif isfield(data, 'extendedNet')
    net = data.extendedNet;
else
    error('Model file does not contain a recognised network variable.');
end
classLabels = data.classLabels;
fprintf('Model loaded. Classes: %s\n\n', strjoin(classLabels, ', '));

%% ---- LOAD IMAGE(S) --------------------------------------------------
if isfolder(IMAGE_PATH)
    % Classify an entire folder of images
    imds = imageDatastore(IMAGE_PATH, ...
        'IncludeSubfolders', false, ...
        'FileExtensions',    {'.jpg','.jpeg','.png'});
    augDS = augmentedImageDatastore(IMAGE_SIZE, imds, ...
        'ColorPreprocessing', 'gray2rgb');

    [predLabels, scores] = classify(net, augDS);

    fprintf('Results:\n');
    fprintf('%-40s %-10s %-10s\n', 'File', 'Prediction', 'Confidence');
    fprintf('%s\n', repmat('-', 1, 65));
    for i = 1:numel(imds.Files)
        [~, fname, ext] = fileparts(imds.Files{i});
        confidence = max(scores(i,:)) * 100;
        fprintf('%-40s %-10s %.1f%%\n', [fname ext], char(predLabels(i)), confidence);
    end

else
    % Classify a single image
    img = imread(IMAGE_PATH);
    img = imresize(img, IMAGE_SIZE(1:2));
    if size(img, 3) == 1
        img = repmat(img, [1 1 3]);   % Convert grayscale to RGB
    end

    [label, scores] = classify(net, img);
    confidence = max(scores) * 100;

    % Display image with prediction
    figure('Name', 'Cloud Classification Result');
    imshow(img);
    title(sprintf('Prediction: %s  (%.1f%% confidence)', char(label), confidence), ...
        'FontSize', 14);

    % Bar chart of all class probabilities
    figure('Name', 'Class Probabilities');
    bar(scores * 100);
    set(gca, 'XTickLabel', classLabels, 'XTickLabelRotation', 45);
    ylabel('Confidence (%)');
    title('Probability for Each Cloud Type');
    grid on;

    fprintf('Prediction : %s\n', char(label));
    fprintf('Confidence : %.1f%%\n\n', confidence);
    fprintf('Full probability breakdown:\n');
    for i = 1:numel(classLabels)
        fprintf('  %-5s : %.2f%%\n', classLabels{i}, scores(i)*100);
    end
end
