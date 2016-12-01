class Score

	attr_accessor :score_status
	attr_accessor :score
	attr_accessor :score_status_modif
	attr_accessor :score_component

	SCORE_STATUS=['unregistered','beginner','casual','expert']

	def initialize (score=1,score_component=[],score_status=SCORE_STATUS[0])
		self.score=score
		self.score_component=score_component
		self.score_status=score_status
		self.score_status_modif=true
	end

#check le type de score requis et recalcul le score de chaque teacher
	def update
		puts self.score_status_modif
		if self.score_status_modif
			puts 1
			case score_status
			
			#unregistered
			when SCORE_STATUS[0]
				puts 2
				self.score_component=[score_admin=Sigmoid.new,
					   score_response=Sigmoid.new,
					   score_connected=Sigmoid.new]

			#beginner
			when SCORE_STATUS[1]
				self.score_component=[]

			#casual
			when SCORE_STATUS[2]
				self.score_component=[]

			#master
			when SCORE_STATUS[3]
				self.score_component=[]				
			end
			self.score_status_modif=false
		end					
		compute
	end

	def compute
		self.score=1
		self.score_component.each do |score_component|
			self.score*=score_component.compute_for
		end
	end
end