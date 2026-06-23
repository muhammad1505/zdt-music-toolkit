#!/usr/bin/env python3
import sys
import os
import time
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# Need to mock watchdog before importing
sys.modules['watchdog'] = MagicMock()
sys.modules['watchdog.observers'] = MagicMock()
sys.modules['watchdog.events'] = MagicMock()

# Since ZDTFileHandler inherits from PatternMatchingEventHandler,
# we need to mock it properly.
class MockPatternMatchingEventHandler:
    def __init__(self, patterns=None, ignore_directories=False, case_sensitive=False):
        pass

sys.modules['watchdog.events'].PatternMatchingEventHandler = MockPatternMatchingEventHandler

# Now import the module
import importlib.util
spec = importlib.util.spec_from_file_location("zdt_watch", os.path.join(os.path.dirname(__file__), "..", "zdt-watch.py"))
zdt_watch = importlib.util.module_from_spec(spec)
sys.modules["zdt_watch"] = zdt_watch
spec.loader.exec_module(zdt_watch)

def test_handler_process():
    handler = zdt_watch.ZDTFileHandler()
    assert len(handler.processed_files) == 0

    with patch('time.sleep') as mock_sleep, \
         patch('subprocess.run') as mock_run, \
         patch('shutil.which', return_value='/mock/bin/zdt'):
        
        # Simulate processing a file
        handler.process('/fake/path/song.mp3')
        
        # Verify it was added to processed set
        assert '/fake/path/song.mp3' in handler.processed_files
        
        # Verify sleep was called (debounce)
        mock_sleep.assert_called_once_with(2)
        
        # Verify subprocess was called with zdt --clean-file
        mock_run.assert_called_once()
        args = mock_run.call_args[0][0]
        assert args[0] == '/mock/bin/zdt'
        assert args[1] == '--clean-file'
        assert args[2] == '/fake/path/song.mp3'
        
        # Try processing the same file again
        handler.process('/fake/path/song.mp3')
        
        # Ensure subprocess was NOT called a second time
        assert mock_run.call_count == 1

def test_handler_events():
    handler = zdt_watch.ZDTFileHandler()
    
    with patch.object(handler, 'process') as mock_process:
        # Simulate create event
        class MockEvent:
            pass
        
        event = MockEvent()
        event.src_path = '/fake/new_song.mp4'
        handler.on_created(event)
        mock_process.assert_called_with('/fake/new_song.mp4')
        
        # Simulate move event
        event.dest_path = '/fake/moved_song.mp3'
        handler.on_moved(event)
        mock_process.assert_called_with('/fake/moved_song.mp3')
