import os
import base64
from PIL import Image

def process_transparency():
    img_path = r"c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\assets\images\google_auth_logo.png"
    output_path = r"c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\assets\images\google_auth_logo.png"
    
    print("Processing transparency for google_auth_logo.png...")
    img = Image.open(img_path).convert("RGBA")
    width, height = img.size
    
    # Load pixels
    pixels = img.load()
    
    # Apply soft-edge background key out
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            brightness = (r + g + b) / 3.0
            if brightness > 245:
                # Calculate alpha based on brightness
                new_a = int(round((255.0 - brightness) * 25.5))
                new_a = max(0, min(255, new_a))
                pixels[x, y] = (r, g, b, new_a)
                
    # Save the transparent image
    img.save(output_path, "PNG")
    print("Transparent logo saved successfully to assets/images/google_auth_logo.png")
    
    # Generate Base64 representation of the transparent image
    with open(output_path, "rb") as image_file:
        encoded_string = base64.b64encode(image_file.read()).decode('utf-8')
        
    base64_path = r"c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\scratch\base64_logo_transparent.txt"
    with open(base64_path, "w", encoding="utf-8") as f:
        f.write(encoded_string)
        
    print(f"Base64 generated, length: {len(encoded_string)}. Saved to scratch/base64_logo_transparent.txt")

if __name__ == "__main__":
    process_transparency()
