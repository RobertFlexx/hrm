# TRM: Terrified ReMove
# `rm` command but files scream when you try to delete them and then explode.
import os
import sys
import subprocess
import playsound3
import random
import time
import threading
import shutil

# SFX dir is (package root)/SFX
# Screams are in (package root)/SFX/Screams
# Explosions are in (package root)/SFX/Explosions
SFX_DIR = os.path.join(os.path.dirname(__file__), 'SFX')
SCREAMS_DIR = os.path.join(SFX_DIR, 'Screams')
EXPLOSIONS_DIR = os.path.join(SFX_DIR, 'Explosions')

threads = []

def get_random_scream():
	screams = [f for f in os.listdir(SCREAMS_DIR) if f.endswith('.mp3') or f.endswith('.wav')]
	return os.path.join(SCREAMS_DIR, random.choice(screams))

def get_random_explosion():
	explosions = [f for f in os.listdir(EXPLOSIONS_DIR) if f.endswith('.mp3') or f.endswith('.wav')]
	return os.path.join(EXPLOSIONS_DIR, random.choice(explosions))

def play_scream_and_explosion():
	# Play scream
	scream = get_random_scream()
	explosion = get_random_explosion()
	playsound3.playsound(scream)

	# Play explosion
	playsound3.playsound(explosion)

def main():
	if len(sys.argv) < 2:
		print("Usage: trm <file1> <file2> ...")
		return

	for file in sys.argv[1:]:
		if not os.path.exists(file):
			print(f"trm: cannot remove '{file}': No such file or directory")
			continue

		# check if directory
		num_files = 1
		is_directory = os.path.isdir(file)
		if is_directory:
			# get amount of files within the directory
			num_files = sum(len(files) for _, _, files in os.walk(file))
			if num_files == 0:
				num_files = 1

		for i in range(num_files):

			# Play scream and explosion in a separate thread so they can play simultaneously
			threads.append(threading.Thread(target=play_scream_and_explosion))
			threads[-1].start()

			# Wait a bit before the next scream/explosion if there are multiple files
			if num_files > 1:
				time.sleep(0.5)

		# Remove the file
		try:
			if is_directory:
				shutil.rmtree(file)
				print(f"'{file}' and its contents have been removed.")
			else:
				os.remove(file)
				print(f"'{file}' has been removed.")
		except Exception as e:
			print(f"trm: cannot remove '{file}': {e}")
		# Wait for all threads to finish before exiting
	for thread in threads:
		thread.join()
