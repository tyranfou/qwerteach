class Sigmoid

# class qui crée des function sigmoid (allant de 0 a 1 en passant par une zone de transition +ou- rapide) , la moyen (mean) centre la function et la porter (range) defini la gamme de valeur qui entreront dans la partie variable de la function. La variable de ponderation (weight) définit l'importance du résultat dans le score final.
	attr_accessor :mean
	attr_accessor :range
	attr_accessor :weight
	def initialize(mean=0,range=1,weight=0.1)
		@mean=mean
		@range=range
		@weight=weight
	end

	def compute_for(var=0)
		1.0+weight*(1.0/(1.0+Math.exp(-range*(var-mean)))-1)
	end
end