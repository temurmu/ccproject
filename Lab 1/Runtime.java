import java.io.*;

public class Runtime {
	public static void main(String[] args) {
		System.out.println("Runtime library for Javalette language.");
	}

	// Print functions
	public static void printInt(int i) {
		System.out.println(i);
	}
	
	public static void printDouble(double d) {
		System.out.println(d);
	}
	
	public static void printString(String s) {
		System.out.println(s);
	}
	
	// Read functions
	public static int readInt() {
		String line = null;
		
		try {
			BufferedReader is = new BufferedReader(new InputStreamReader(System.in));
			line = is.readLine();
			return Integer.parseInt(line);
			
		} catch (NumberFormatException ex) {
			System.err.println("Not a valid number: " + line);
			
		} catch (IOException e) {
			System.err.println("Unexpected IO ERROR: " + e);
			
		}
		
		return -1;
	}
	
	public static double readDouble() {
		String line = null;
		
		try {
			BufferedReader is = new BufferedReader(new InputStreamReader(System.in));
			line = is.readLine();
			return Double.parseDouble(line);
			
		} catch (NumberFormatException ex) {
			System.err.println("Not a valid number: " + line);
			
		} catch (IOException e) {
			System.err.println("Unexpected IO ERROR: " + e);
			
		}
		
		return -1.0;
	}
	
	
}