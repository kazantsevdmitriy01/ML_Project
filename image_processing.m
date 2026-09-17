%% =========================================================
%  IMAGE COLLECTION PREPROCESSOR
%
%  Takes raw collected images (mixed formats, sizes, aspect
%  ratios) and converts them into standardised 256x256 JPEGs
%  ready for training.
%
%  Features:
%    - Handles .jpg, .jpeg, .png, .bmp, .tiff, .heic, .webp
%    - Converts HEIC (iPhone) images automatically
%    - Wide images (landscape) are split into 2 square crops
%    - Tall images (portrait) are centre-cropped to square
%    - All output is 256x256 RGB JPEG
%
%  Usage:
%    1. Put your raw images into raw_images/Mammatus/
%       (or raw_images/Virga/ etc.)
%    2. Set CLASS_NAME below
%    3. Run script
%    4. Check output in data/Mammatus/ before training
% =========================================================

clc; clear; close all;

%% ---- CONFIGURATION --------------------------------------------------
CLASS_NAME   = 'Virga_Wk';        % Folder name = class label
RAW_DIR      = 'raw_images';      % Where your raw images are
OUTPUT_DIR   = 'data';            % Your training data folder
TARGET_SIZE  = [256 256];         % Must match CCSN dataset
JPEG_QUALITY = 95;                % Output JPEG quality (0-100)

% Aspect ratio threshold for wide-image splitting
% Images wider than this ratio (width/height) get split into 2 crops
% 1.5 means anything wider than 3:2 gets split
WIDE_RATIO_THRESHOLD = 1.5;

% Valid input extensions to look for
VALID_EXTS = {'.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.tif', '.webp'};
HEIC_EXTS  = {'.heic', '.HEIC'};

%% ---- SETUP ----------------------------------------------------------
inputPath  = fullfile(RAW_DIR, CLASS_NAME);
outputPath = fullfile(OUTPUT_DIR, CLASS_NAME);

if ~exist(inputPath, 'dir')
    error('Input folder not found: %s\nPlease create it and add your images.', inputPath);
end

if ~exist(outputPath, 'dir')
    mkdir(outputPath);
    fprintf('Created output folder: %s\n', outputPath);
end

% Temp folder for HEIC conversions
tempDir = fullfile(RAW_DIR, 'temp_converted');
if ~exist(tempDir, 'dir'), mkdir(tempDir); end

%% ---- FIND ALL IMAGE FILES -------------------------------------------
fprintf('=== Scanning for images in: %s ===\n\n', inputPath);

% Find standard format images
allFiles = [];
for e = 1:numel(VALID_EXTS)
    found = dir(fullfile(inputPath, ['*' VALID_EXTS{e}]));
    allFiles = [allFiles; found];  %#ok
end

% Find HEIC files separately
heicFiles = [];
for e = 1:numel(HEIC_EXTS)
    found = dir(fullfile(inputPath, ['*' HEIC_EXTS{e}]));
    heicFiles = [heicFiles; found];  %#ok
end

fprintf('Found %d standard images (.jpg/.png etc.)\n', numel(allFiles));
fprintf('Found %d HEIC images (iPhone format)\n\n',    numel(heicFiles));

%% ---- CONVERT HEIC FILES ---------------------------------------------
% HEIC is Apple's format — MATLAB can't read it directly.
% We convert to PNG first using one of two methods.

if numel(heicFiles) > 0
    fprintf('=== Converting HEIC files ===\n');

    % Method 1: Try MATLAB native (R2022b+ only)
    matlabCanReadHEIC = false;
    try
        testFile = fullfile(inputPath, heicFiles(1).name);
        imread(testFile);
        matlabCanReadHEIC = true;
        fprintf('MATLAB native HEIC support detected.\n');
    catch
        fprintf('MATLAB cannot read HEIC natively. Trying ImageMagick...\n');
    end

    if matlabCanReadHEIC
        % Just add HEIC files directly to the processing queue
        allFiles = [allFiles; heicFiles];  %#ok

    else
        % Method 2: Use ImageMagick (must be installed on system)
        % Download from: https://imagemagick.org/script/download.php
        imageMagickAvailable = (system('magick --version') == 0) || ...
                               (system('convert --version') == 0);

        if imageMagickAvailable
            fprintf('ImageMagick found. Converting HEIC files...\n');
            for i = 1:numel(heicFiles)
                inFile  = fullfile(inputPath, heicFiles(i).name);
                [~, baseName, ~] = fileparts(heicFiles(i).name);
                outFile = fullfile(tempDir, [baseName '.png']);

                % Try 'magick' (Windows) then 'convert' (Mac/Linux)
                cmd = sprintf('magick "%s" "%s"', inFile, outFile);
                if system(cmd) ~= 0
                    cmd = sprintf('convert "%s" "%s"', inFile, outFile);
                    system(cmd);
                end

                if exist(outFile, 'file')
                    % Add converted file to processing queue
                    newEntry      = heicFiles(i);
                    newEntry.name = [baseName '.png'];
                    newEntry.folder = tempDir;
                    allFiles = [allFiles; newEntry];  %#ok
                    fprintf('  Converted: %s\n', heicFiles(i).name);
                else
                    fprintf('  FAILED to convert: %s (skipping)\n', heicFiles(i).name);
                end
            end
        else
            fprintf('\n*** WARNING: Cannot convert HEIC files ***\n');
            fprintf('ImageMagick is not installed on your system.\n');
            fprintf('To fix this:\n');
            fprintf('  1. Download from: https://imagemagick.org/script/download.php\n');
            fprintf('  2. Install and restart MATLAB\n');
            fprintf('  3. Re-run this script\n');
            fprintf('HEIC files will be skipped for now.\n\n');
        end
    end
end

fprintf('\nTotal images to process: %d\n\n', numel(allFiles));

%% ---- PROCESS EACH IMAGE ---------------------------------------------
fprintf('=== Processing images ===\n\n');

outputCount = 0;
skipCount   = 0;

for i = 1:numel(allFiles)

    % Build full path — handle temp dir conversions
    if isfield(allFiles(i), 'folder') && ~isempty(allFiles(i).folder)
        inputFile = fullfile(allFiles(i).folder, allFiles(i).name);
    else
        inputFile = fullfile(inputPath, allFiles(i).name);
    end

    [~, baseName, ext] = fileparts(allFiles(i).name);
    fprintf('Processing [%d/%d]: %s\n', i, numel(allFiles), allFiles(i).name);

    try
        %% Read and normalise the image
        img = imread(inputFile);

        % Convert grayscale to RGB
        if size(img, 3) == 1
            img = repmat(img, [1 1 3]);
        end

        % Drop alpha channel (RGBA → RGB)
        if size(img, 3) == 4
            img = img(:,:,1:3);
        end

        % Ensure uint8
        if ~isa(img, 'uint8')
            img = im2uint8(img);
        end

        %% Determine crop strategy based on aspect ratio
        [h, w, ~] = size(img);
        aspectRatio = w / h;

        if aspectRatio >= WIDE_RATIO_THRESHOLD
            %% WIDE IMAGE — split into 2 square crops
            % We take a left crop and a right crop, each centred
            % vertically and covering the full height

            fprintf('  → Wide image (%.1f:1) — splitting into 2 crops\n', aspectRatio);

            % Each crop is h x h (full height, square)
            cropSize = h;

            % Left crop: starts at left edge, centred vertically
            leftCrop  = img(1:h, 1:cropSize, :);

            % Right crop: starts at right edge going left
            rightCrop = img(1:h, (w - cropSize + 1):w, :);

            % Resize both to target size and save
            crops     = {leftCrop, rightCrop};
            suffixes  = {'_cropL', '_cropR'};

            for c = 1:2
                croppedImg   = imresize(crops{c}, TARGET_SIZE);
                outputName   = sprintf('%s_%04d%s.jpg', CLASS_NAME, outputCount + 1, suffixes{c});
                outputFile   = fullfile(outputPath, outputName);
                imwrite(croppedImg, outputFile, 'jpg', 'Quality', JPEG_QUALITY);
                outputCount  = outputCount + 1;
                fprintf('  → Saved: %s\n', outputName);
            end

        elseif aspectRatio < (1 / WIDE_RATIO_THRESHOLD)
            %% TALL IMAGE — centre crop to square
            fprintf('  → Tall image — centre cropping to square\n');

            cropSize  = w;   % Square side = width
            topOffset = floor((h - cropSize) / 2);
            centreImg = img(topOffset+1 : topOffset+cropSize, :, :);
            resized   = imresize(centreImg, TARGET_SIZE);

            outputName = sprintf('%s_%04d.jpg', CLASS_NAME, outputCount + 1);
            outputFile = fullfile(outputPath, outputName);
            imwrite(resized, outputFile, 'jpg', 'Quality', JPEG_QUALITY);
            outputCount = outputCount + 1;
            fprintf('  → Saved: %s\n', outputName);

        else
            %% ROUGHLY SQUARE — just resize directly
            resized    = imresize(img, TARGET_SIZE);
            outputName = sprintf('%s_%04d.jpg', CLASS_NAME, outputCount + 1);
            outputFile = fullfile(outputPath, outputName);
            imwrite(resized, outputFile, 'jpg', 'Quality', JPEG_QUALITY);
            outputCount = outputCount + 1;
            fprintf('  → Saved: %s\n', outputName);
        end

    catch err
        fprintf('  *** SKIPPED: %s\n      Reason: %s\n', allFiles(i).name, err.message);
        skipCount = skipCount + 1;
    end
end

%% ---- CLEANUP TEMP FILES ---------------------------------------------
if exist(tempDir, 'dir')
    rmdir(tempDir, 's');
end

%% ---- SUMMARY --------------------------------------------------------
fprintf('\n=== Done ===\n');
fprintf('Images processed : %d input → %d output files\n', numel(allFiles), outputCount);
fprintf('Skipped          : %d\n', skipCount);
fprintf('Output folder    : %s\n\n', outputPath);

% Quick visual check — show a random sample of output images
fprintf('Displaying sample of output images for visual check...\n');
outputFiles = dir(fullfile(outputPath, '*.jpg'));

if numel(outputFiles) > 0
    sampleN = min(12, numel(outputFiles));
    randIdx = randperm(numel(outputFiles), sampleN);

    figure('Name', 'Output Sample — check these look correct');
    for k = 1:sampleN
        img = imread(fullfile(outputPath, outputFiles(randIdx(k)).name));
        subplot(3, 4, k);
        imshow(img);
        title(outputFiles(randIdx(k)).name, 'FontSize', 7, 'Interpreter', 'none');
    end
    sgtitle(sprintf('%s — Sample Output Images', CLASS_NAME));
end

fprintf('\nNext steps:\n');
fprintf('  1. Review the sample images above — delete any bad ones from %s\n', outputPath);
fprintf('  2. Repeat this script with CLASS_NAME = ''Virga'' for Virga images\n');
fprintf('  3. Once happy, run add_new_class.m to retrain\n');