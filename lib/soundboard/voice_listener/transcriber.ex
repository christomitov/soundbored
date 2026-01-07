defmodule Soundboard.VoiceListener.Transcriber do
  @moduledoc """
  Handles speech-to-text transcription using local whisper.cpp.
  
  Converts raw audio data (Opus) to WAV and runs whisper.cpp for transcription.
  Optimized for low latency with the tiny/base model.
  """
  require Logger
  
  # Path to whisper.cpp binary and model
  @whisper_bin Application.compile_env(:soundboard, :whisper_bin, "/usr/local/bin/whisper")
  @whisper_model Application.compile_env(:soundboard, :whisper_model, "base.en")
  
  @doc """
  Transcribes audio data using local whisper.cpp.
  
  Returns {:ok, text} on success, {:error, reason} on failure.
  """
  def transcribe(audio_data) when is_binary(audio_data) and byte_size(audio_data) > 0 do
    with {:ok, wav_path} <- convert_to_wav(audio_data),
         {:ok, text} <- run_whisper(wav_path) do
      {:ok, String.trim(text), nil}
    end
  end
  
  def transcribe(_), do: {:error, :empty_audio}
  
  defp convert_to_wav(opus_data) do
    tmp_input = "/tmp/voice_#{:erlang.unique_integer([:positive])}.opus"
    tmp_output = "/tmp/voice_#{:erlang.unique_integer([:positive])}.wav"
    
    try do
      File.write!(tmp_input, opus_data)
      
      # Convert to 16kHz mono WAV (required by whisper)
      case System.cmd("ffmpeg", [
        "-y", 
        "-f", "opus",
        "-i", tmp_input,
        "-ar", "16000",
        "-ac", "1",
        "-c:a", "pcm_s16le",
        "-f", "wav",
        tmp_output
      ], stderr_to_stdout: true) do
        {_, 0} ->
          {:ok, tmp_output}
        {output, code} ->
          Logger.warning("ffmpeg conversion failed (code #{code}): #{output}")
          File.rm(tmp_input)
          {:error, :ffmpeg_failed}
      end
    rescue
      e ->
        File.rm(tmp_input)
        {:error, {:conversion_error, e}}
    after
      File.rm(tmp_input)
    end
  end
  
  defp run_whisper(wav_path) do
    whisper_bin = Application.get_env(:soundboard, :whisper_bin, @whisper_bin)
    whisper_model = Application.get_env(:soundboard, :whisper_model, @whisper_model)
    models_dir = Application.get_env(:soundboard, :whisper_models_dir, "/usr/local/share/whisper")
    
    model_path = Path.join(models_dir, "ggml-#{whisper_model}.bin")
    
    unless File.exists?(whisper_bin) do
      Logger.error("whisper.cpp binary not found at #{whisper_bin}")
      {:error, :whisper_not_found}
    else
      args = [
        "-m", model_path,
        "-f", wav_path,
        "-nt",           # no timestamps
        "-np",           # no prints (progress)
        "--no-fallback", # don't fallback to other models
        "-t", "4",       # threads
        "-l", "en"       # language
      ]
      
      Logger.debug("Running whisper: #{whisper_bin} #{Enum.join(args, " ")}")
      
      case System.cmd(whisper_bin, args, stderr_to_stdout: true) do
        {output, 0} ->
          # Clean up wav file
          File.rm(wav_path)
          # Extract just the transcribed text (whisper outputs some metadata)
          text = output
          |> String.split("\n")
          |> Enum.reject(&String.starts_with?(&1, "["))
          |> Enum.join(" ")
          |> String.trim()
          
          {:ok, text}
        {output, code} ->
          Logger.warning("whisper.cpp failed (code #{code}): #{output}")
          File.rm(wav_path)
          {:error, {:whisper_failed, code}}
      end
    end
  end
end
